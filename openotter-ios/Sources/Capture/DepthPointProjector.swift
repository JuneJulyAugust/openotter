import CoreGraphics
import CoreVideo
import simd

/// Projects ARKit depth pixels into world-space points with explicit camera-model math.
///
/// The equations match `.ai-context/coordinate-systems.md`:
/// - x_cam =  (u - cx) * d / fx
/// - y_cam = -(v - cy) * d / fy
/// - z_cam = -d
struct DepthPointProjector {
    struct Result {
        let points: [PackedPoint]
        let centroid: SIMD3<Float>?
    }

    /// Distance range used for debug color ramping only.
    /// It does not alter geometry.
    let colorRangeMeters: Float

    init(colorRangeMeters: Float = 5.0) {
        self.colorRangeMeters = max(colorRangeMeters, 0.001)
    }

    func project(
        depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer?,
        intrinsics: simd_float3x3,
        imageResolution: CGSize,
        cameraTransform: simd_float4x4
    ) -> Result {
        guard imageResolution.width > 0, imageResolution.height > 0 else {
            return Result(points: [], centroid: nil)
        }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        if let confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        }
        defer {
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
        }

        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else {
            return Result(points: [], centroid: nil)
        }

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let depthStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float>.size
        let depthPointer = depthBase.assumingMemoryBound(to: Float.self)

        let confidencePointer: UnsafePointer<UInt8>?
        let confidenceStride: Int
        if let confidenceMap, let confidenceBase = CVPixelBufferGetBaseAddress(confidenceMap) {
            confidencePointer = UnsafeRawPointer(confidenceBase).assumingMemoryBound(to: UInt8.self)
            confidenceStride = CVPixelBufferGetBytesPerRow(confidenceMap)
        } else {
            confidencePointer = nil
            confidenceStride = 0
        }

        // Intrinsics are defined at camera image resolution.
        // Scale them into depth-map resolution before projection.
        let scaleX = Float(depthWidth) / Float(imageResolution.width)
        let scaleY = Float(depthHeight) / Float(imageResolution.height)
        let fx = intrinsics[0][0] * scaleX
        let fy = intrinsics[1][1] * scaleY
        let cx = intrinsics[2][0] * scaleX
        let cy = intrinsics[2][1] * scaleY

        guard fx.isFinite, fy.isFinite, abs(fx) > .ulpOfOne, abs(fy) > .ulpOfOne else {
            return Result(points: [], centroid: nil)
        }

        var points: [PackedPoint] = []
        points.reserveCapacity(depthWidth * depthHeight / 2)
        var centroidSum = SIMD3<Float>.zero

        for v in 0..<depthHeight {
            for u in 0..<depthWidth {
                let depthMeters = depthPointer[v * depthStride + u]
                guard depthMeters > 0, depthMeters.isFinite else { continue }

                if let confidencePointer, confidencePointer[v * confidenceStride + u] == 0 {
                    continue
                }

                let xCam = (Float(u) - cx) * depthMeters / fx
                let yCam = -(Float(v) - cy) * depthMeters / fy
                let zCam = -depthMeters

                let worldPoint = cameraTransform * SIMD4<Float>(xCam, yCam, zCam, 1.0)
                let position = SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
                centroidSum += position

                let normalizedDistance = min(max(depthMeters / colorRangeMeters, 0.0), 1.0)
                let (r, g, b) = distanceColor(normalizedDistance)

                points.append(PackedPoint(position: position, r: r, g: g, b: b, a: 255))
            }
        }

        let centroid = points.isEmpty ? nil : centroidSum / Float(points.count)
        return Result(points: points, centroid: centroid)
    }

    private func distanceColor(_ t: Float) -> (UInt8, UInt8, UInt8) {
        let r: Float
        let g: Float
        let b: Float

        if t < 0.25 {
            let s = t / 0.25
            r = 1.0
            g = s
            b = 0.0
        } else if t < 0.5 {
            let s = (t - 0.25) / 0.25
            r = 1.0 - s
            g = 1.0
            b = 0.0
        } else if t < 0.75 {
            let s = (t - 0.5) / 0.25
            r = 0.0
            g = 1.0 - s
            b = s
        } else {
            let s = (t - 0.75) / 0.25
            r = 0.0
            g = 0.0
            b = 1.0 - s * 0.5
        }

        return (
            UInt8(clamping: Int(r * 255)),
            UInt8(clamping: Int(g * 255)),
            UInt8(clamping: Int(b * 255))
        )
    }
}
