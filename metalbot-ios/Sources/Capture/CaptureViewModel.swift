import CoreImage
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

    let renderer = PointCloudRenderer()
    private let captureSession = LiDARCaptureSession()
    nonisolated(unsafe) private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var fpsTracker = FPSTracker()

    func startCapture() {
        state = .requesting

        Task {
            guard DeviceCapability.isLiDARAvailable else {
                state = .error("LiDAR not available on this device.")
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
        captureSession.stop()
        state = .idle
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
        let cgImage = convertCameraImage(frame.cameraImage, orientation: frame.orientation)

        let modeLabel = renderer.viewMode == .cameraPOV ? "Camera POV" : "Orbit"
        let depthRes = "\(frame.depthResolution.w)x\(frame.depthResolution.h)"
        let imgRes = "\(frame.imageResolution.w)x\(frame.imageResolution.h)"
        let fovDeg = frame.verticalFov * 180 / .pi
        let ptCount = frame.pointCloud.count

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.renderer.update(
                cloud: frame.pointCloud,
                cameraTransform: frame.cameraTransform,
                viewMatrix: frame.viewMatrix,
                verticalFov: frame.verticalFov
            )
            self.cameraImage = cgImage
            self.fpsTracker.tick()
            self.diagnostics = FrameDiagnostics(
                fps: self.fpsTracker.fps,
                pointCount: ptCount,
                depthResolution: depthRes,
                imageResolution: imgRes,
                viewMode: modeLabel,
                fovDeg: fovDeg
            )
        }
    }

    /// Convert CVPixelBuffer to CGImage with correct rotation for current interface orientation.
    private nonisolated func convertCameraImage(
        _ pixelBuffer: CVPixelBuffer,
        orientation: UIInterfaceOrientation
    ) -> CGImage? {
        let ciOrientation: CGImagePropertyOrientation
        switch orientation {
        case .portrait:          ciOrientation = .right
        case .portraitUpsideDown: ciOrientation = .left
        case .landscapeLeft:     ciOrientation = .down
        case .landscapeRight:    ciOrientation = .up
        default:                 ciOrientation = .right
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(ciOrientation)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
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
}
