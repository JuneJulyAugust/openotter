import ARKit
import simd
import UIKit

protocol CaptureFrameDelegate: AnyObject {
    func didReceive(_ frame: CaptureFrame)
}

/// Owns an ARSession configured for LiDAR scene depth.
/// Back-projects depth pixels to world-space 3D points and delivers CaptureFrame per frame.
final class LiDARCaptureSession: NSObject {
    weak var delegate: CaptureFrameDelegate?

    private let arSession = ARSession()
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
        arSession.delegate = self
    }

    func start() {
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth]
        arSession.run(config)
    }

    func stop() {
        arSession.pause()
    }

    // MARK: - Orientation mapping

    /// Map UIDeviceOrientation → UIInterfaceOrientation.
    /// UIDevice and UIInterface orientations have inverted landscape mappings.
    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        let device = UIDevice.current.orientation
        switch device {
        case .portrait:          return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft:     return .landscapeRight
        case .landscapeRight:    return .landscapeLeft
        default:                 return .portrait
        }
    }
}

// MARK: - ARSessionDelegate

extension LiDARCaptureSession: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let sceneDepth = frame.sceneDepth else { return }

        let ts = frame.timestamp
        guard ts > lastTimestamp else { return }
        lastTimestamp = ts

        let depthMap = sceneDepth.depthMap
        let depthW = CVPixelBufferGetWidth(depthMap)
        let depthH = CVPixelBufferGetHeight(depthMap)

        let orientation = currentInterfaceOrientation()

        // ARKit orientation-aware view matrix (handles portrait/landscape rotation)
        let viewMatrix = frame.camera.viewMatrix(for: orientation)

        // Compute vertical FOV adjusted for interface orientation.
        // In portrait, the viewport's vertical axis corresponds to the camera's horizontal axis.
        let fx = frame.camera.intrinsics[0][0]
        let fy = frame.camera.intrinsics[1][1]
        let imageRes = frame.camera.imageResolution
        let verticalFov: Float = orientation.isPortrait
            ? 2 * atan(Float(imageRes.width) / (2 * fx))
            : 2 * atan(Float(imageRes.height) / (2 * fy))

        let points = backProject(
            depthMap: depthMap,
            confidenceMap: sceneDepth.confidenceMap,
            intrinsics: frame.camera.intrinsics,
            imageResolution: imageRes,
            cameraTransform: frame.camera.transform
        )

        let captureFrame = CaptureFrame(
            pointCloud: PointCloud(timestamp: ts, points: points),
            cameraTransform: frame.camera.transform,
            viewMatrix: viewMatrix,
            verticalFov: verticalFov,
            cameraImage: frame.capturedImage,
            orientation: orientation,
            depthResolution: (depthW, depthH),
            imageResolution: (Int(imageRes.width), Int(imageRes.height))
        )

        delegate?.didReceive(captureFrame)
    }
}

// MARK: - Back-projection

extension LiDARCaptureSession {
    /// Back-project depth pixels to world-space 3D points.
    /// See .ai-context/coordinate-systems.md for derivation.
    private func backProject(
        depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer?,
        intrinsics: simd_float3x3,
        imageResolution: CGSize,
        cameraTransform: simd_float4x4
    ) -> [PackedPoint] {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        if let confMap = confidenceMap {
            CVPixelBufferLockBaseAddress(confMap, .readOnly)
        }
        defer {
            if let confMap = confidenceMap {
                CVPixelBufferUnlockBaseAddress(confMap, .readOnly)
            }
        }

        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return [] }

        let w = CVPixelBufferGetWidth(depthMap)
        let h = CVPixelBufferGetHeight(depthMap)
        let depthStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float>.size
        let depthPtr = depthBase.assumingMemoryBound(to: Float.self)

        let confPtr: UnsafeMutablePointer<UInt8>?
        let confStride: Int
        if let confMap = confidenceMap,
           let confBase = CVPixelBufferGetBaseAddress(confMap) {
            confPtr = confBase.assumingMemoryBound(to: UInt8.self)
            confStride = CVPixelBufferGetBytesPerRow(confMap)
        } else {
            confPtr = nil
            confStride = 0
        }

        // Scale intrinsics from image resolution to depth map resolution
        let scaleX = Float(w) / Float(imageResolution.width)
        let scaleY = Float(h) / Float(imageResolution.height)
        let fx = intrinsics[0][0] * scaleX
        let fy = intrinsics[1][1] * scaleY
        let cx = intrinsics[2][0] * scaleX
        let cy = intrinsics[2][1] * scaleY

        var points: [PackedPoint] = []
        points.reserveCapacity(w * h / 2)

        let maxRange: Float = 5.0

        for v in 0..<h {
            for u in 0..<w {
                let d = depthPtr[v * depthStride + u]
                guard d > 0 && d.isFinite else { continue }

                if let conf = confPtr, conf[v * confStride + u] == 0 {
                    continue
                }

                // ARKit camera space: +X right, +Y up, -Z forward
                let xCam = (Float(u) - cx) * d / fx
                let yCam = -(Float(v) - cy) * d / fy
                let zCam = -d

                let worldPt = cameraTransform * SIMD4<Float>(xCam, yCam, zCam, 1.0)

                let t = min(d / maxRange, 1.0)
                let (r, g, b) = distanceColor(t)

                points.append(PackedPoint(
                    position: SIMD3<Float>(worldPt.x, worldPt.y, worldPt.z),
                    r: r, g: g, b: b, a: 255
                ))
            }
        }

        return points
    }

    private func distanceColor(_ t: Float) -> (UInt8, UInt8, UInt8) {
        let r: Float, g: Float, b: Float

        if t < 0.25 {
            let s = t / 0.25
            r = 1.0; g = s; b = 0.0
        } else if t < 0.5 {
            let s = (t - 0.25) / 0.25
            r = 1.0 - s; g = 1.0; b = 0.0
        } else if t < 0.75 {
            let s = (t - 0.5) / 0.25
            r = 0.0; g = 1.0 - s; b = s
        } else {
            let s = (t - 0.75) / 0.25
            r = 0.0; g = 0.0; b = 1.0 - s * 0.5
        }

        return (
            UInt8(clamping: Int(r * 255)),
            UInt8(clamping: Int(g * 255)),
            UInt8(clamping: Int(b * 255))
        )
    }
}
