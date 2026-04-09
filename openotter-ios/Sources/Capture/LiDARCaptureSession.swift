import ARKit
import simd
import UIKit

protocol CaptureFrameDelegate: AnyObject {
    func didReceive(_ frame: CaptureFrame)
}

/// Owns an ARSession configured for LiDAR scene depth.
/// Produces `CaptureFrame` objects using deterministic projection math.
final class LiDARCaptureSession: NSObject {
    weak var delegate: CaptureFrameDelegate?

    private let arSession = ARSession()
    private let frameQueue = DispatchQueue(label: "com.openotter.capture.frame", qos: .userInitiated)
    private let frameProjector = DepthPointProjector()
    private var isConfigured = false
    private var isRunning = false
    private var lastTimestamp: TimeInterval = 0

    enum SessionError: Error, CustomStringConvertible {
        case sceneDepthUnsupported

        var description: String {
            switch self {
            case .sceneDepthUnsupported:
                return "LiDAR scene depth not supported on this device."
            }
        }
    }

    func configure() throws {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            throw SessionError.sceneDepthUnsupported
        }
        guard !isConfigured else { return }

        arSession.delegate = self
        arSession.delegateQueue = frameQueue
        isConfigured = true
    }

    func start() {
        guard isConfigured else { return }
        guard !isRunning else { return }

        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth]
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }

        isRunning = false
        lastTimestamp = 0
        arSession.pause()
    }

    deinit {
        arSession.pause()
        arSession.delegate = nil
    }

    // MARK: - Orientation mapping

    /// Fetches the active interface orientation from the foreground UIWindowScene.
    /// This matches actual UI rotation even when UIDevice orientation is ambiguous.
    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        if Thread.isMainThread {
            return interfaceOrientationOnMain()
        }

        return DispatchQueue.main.sync { interfaceOrientationOnMain() }
    }

    private func interfaceOrientationOnMain() -> UIInterfaceOrientation {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        if let activeScene = windowScenes.first(where: { $0.activationState == .foregroundActive }) {
            return activeScene.interfaceOrientation
        }

        if let knownScene = windowScenes.first(where: { $0.interfaceOrientation != .unknown }) {
            return knownScene.interfaceOrientation
        }

        return .portrait
    }

    private func computeVerticalFov(
        intrinsics: simd_float3x3,
        imageResolution: CGSize,
        orientation: UIInterfaceOrientation
    ) -> Float {
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]

        guard fx.isFinite, fy.isFinite, fx > .ulpOfOne, fy > .ulpOfOne else {
            return Float.pi / 3
        }

        if orientation.isPortrait {
            return 2 * atan(Float(imageResolution.width) / (2 * fx))
        }

        return 2 * atan(Float(imageResolution.height) / (2 * fy))
    }
}

// MARK: - ARSessionDelegate

extension LiDARCaptureSession: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRunning, let sceneDepth = frame.sceneDepth else { return }

        let timestamp = frame.timestamp
        guard timestamp > lastTimestamp else { return }
        lastTimestamp = timestamp

        autoreleasepool {
            let depthMap = sceneDepth.depthMap
            let depthWidth = CVPixelBufferGetWidth(depthMap)
            let depthHeight = CVPixelBufferGetHeight(depthMap)
            let orientation = currentInterfaceOrientation()
            let imageResolution = frame.camera.imageResolution
            let verticalFov = computeVerticalFov(
                intrinsics: frame.camera.intrinsics,
                imageResolution: imageResolution,
                orientation: orientation
            )

            let projection = frameProjector.project(
                depthMap: depthMap,
                confidenceMap: sceneDepth.confidenceMap,
                intrinsics: frame.camera.intrinsics,
                imageResolution: imageResolution,
                cameraTransform: frame.camera.transform
            )

            let captureFrame = CaptureFrame(
                pointCloud: PointCloud(
                    timestamp: timestamp,
                    points: projection.points,
                    centroid: projection.centroid
                ),
                cameraTransform: frame.camera.transform,
                viewMatrix: frame.camera.viewMatrix(for: orientation),
                verticalFov: verticalFov,
                cameraImage: frame.capturedImage,
                orientation: orientation,
                depthResolution: (depthWidth, depthHeight),
                imageResolution: (Int(imageResolution.width), Int(imageResolution.height))
            )

            delegate?.didReceive(captureFrame)
        }
    }
}
