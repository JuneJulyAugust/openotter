import CoreImage
import Foundation
import SwiftUI

enum CaptureState: Equatable {
    case idle
    case requesting
    case running
    case error(String)
}

struct FrameDiagnostics {
    var fps: Double = 0
    var pointCount: Int = 0
    var depthResolution: String = ""
    var imageResolution: String = ""
    var viewMode: String = ""
    var fovDeg: Float = 0
}

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var state: CaptureState = .idle
    @Published var diagnostics = FrameDiagnostics()
    @Published var cameraImage: CGImage?
    @Published private(set) var renderer: PointCloudRenderer?

    private let captureSession = LiDARCaptureSession()
    nonisolated(unsafe) private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    nonisolated(unsafe) private let frameDrainLock = NSLock()
    nonisolated(unsafe) private var pendingFrame: CaptureFrame?
    nonisolated(unsafe) private var isFrameDrainScheduled = false
    private var fpsTracker = FPSTracker()

    func startCapture() {
        guard state != .running, state != .requesting else { return }
        state = .requesting

        Task {
            guard DeviceCapability.isLiDARAvailable else {
                state = .error("LiDAR not available on this device.")
                return
            }

            do {
                try prepareRendererIfNeeded()
            } catch {
                state = .error(error.localizedDescription)
                return
            }

            let authorized = await requestCameraPermission()
            guard authorized else {
                state = .error("Camera access denied. Enable in Settings.")
                return
            }

            do {
                try captureSession.configure()
                captureSession.delegate = self
                captureSession.start()
                state = .running
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func stopCapture() {
        captureSession.delegate = nil
        captureSession.stop()
        cameraImage = nil
        diagnostics = FrameDiagnostics()
        fpsTracker.reset()
        frameDrainLock.sync {
            pendingFrame = nil
            isFrameDrainScheduled = false
        }
        state = .idle
    }

    private func prepareRendererIfNeeded() throws {
        guard renderer == nil else { return }
        renderer = try PointCloudRenderer.make()
    }

    private func requestCameraPermission() async -> Bool {
        switch DeviceCapability.cameraAuthorizationStatus {
        case .authorized:
            return true
        case .notDetermined:
            return await DeviceCapability.requestCameraAccess()
        default:
            return false
        }
    }
}

// MARK: - CaptureFrameDelegate

extension CaptureViewModel: CaptureFrameDelegate {
    nonisolated func didReceive(_ frame: CaptureFrame) {
        let shouldSchedule = frameDrainLock.sync { () -> Bool in
            pendingFrame = frame
            guard !isFrameDrainScheduled else { return false }
            isFrameDrainScheduled = true
            return true
        }

        guard shouldSchedule else { return }

        Task { @MainActor [weak self] in
            await self?.drainPendingFrames()
        }
    }

    @MainActor
    private func drainPendingFrames() async {
        while true {
            let nextFrame = frameDrainLock.sync { () -> CaptureFrame? in
                guard let frame = pendingFrame else {
                    isFrameDrainScheduled = false
                    return nil
                }
                pendingFrame = nil
                return frame
            }

            guard let nextFrame else { break }
            apply(frame: nextFrame)
            await Task.yield()
        }
    }

    @MainActor
    private func apply(frame: CaptureFrame) {
        guard state == .running, let renderer else { return }

        renderer.update(
            cloud: frame.pointCloud,
            cameraTransform: frame.cameraTransform,
            viewMatrix: frame.viewMatrix,
            verticalFov: frame.verticalFov
        )
        cameraImage = convertCameraImage(frame.cameraImage, orientation: frame.orientation)

        fpsTracker.tick()
        diagnostics = makeDiagnostics(frame: frame, renderer: renderer)
    }

    @MainActor
    private func makeDiagnostics(frame: CaptureFrame, renderer: PointCloudRenderer) -> FrameDiagnostics {
        let modeLabel = renderer.viewMode == .cameraPOV ? "Camera POV" : "Orbit"
        let depthRes = "\(frame.depthResolution.w)x\(frame.depthResolution.h)"
        let imageRes = "\(frame.imageResolution.w)x\(frame.imageResolution.h)"
        let fovDegrees = frame.verticalFov * 180 / .pi

        return FrameDiagnostics(
            fps: fpsTracker.fps,
            pointCount: frame.pointCloud.count,
            depthResolution: depthRes,
            imageResolution: imageRes,
            viewMode: modeLabel,
            fovDeg: fovDegrees
        )
    }

    /// Convert CVPixelBuffer to CGImage with correct rotation for current interface orientation.
    private nonisolated func convertCameraImage(
        _ pixelBuffer: CVPixelBuffer,
        orientation: UIInterfaceOrientation
    ) -> CGImage? {
        autoreleasepool {
            let ciOrientation: CGImagePropertyOrientation
            switch orientation {
            case .portrait:
                ciOrientation = .right
            case .portraitUpsideDown:
                ciOrientation = .left
            case .landscapeLeft:
                ciOrientation = .down
            case .landscapeRight:
                ciOrientation = .up
            default:
                ciOrientation = .right
            }

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(ciOrientation)
            return ciContext.createCGImage(ciImage, from: ciImage.extent)
        }
    }
}

// MARK: - FPS Tracker

private struct FPSTracker {
    private var timestamps: [CFAbsoluteTime] = []
    private let windowSize = 30

    var fps: Double {
        guard timestamps.count >= 2,
              let first = timestamps.first,
              let last = timestamps.last else {
            return 0
        }
        let elapsed = last - first
        guard elapsed > 0 else { return 0 }
        return Double(timestamps.count - 1) / elapsed
    }

    mutating func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        timestamps.append(now)
        if timestamps.count > windowSize {
            timestamps.removeFirst(timestamps.count - windowSize)
        }
    }

    mutating func reset() {
        timestamps.removeAll(keepingCapacity: true)
    }
}

private extension NSLock {
    func sync<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
