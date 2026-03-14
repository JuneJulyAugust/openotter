import CoreVideo
import Foundation
import simd
import UIKit

/// Packed point for Metal vertex buffer: position + RGBA color.
/// 16-byte aligned for GPU efficiency.
struct PackedPoint {
    var position: SIMD3<Float>
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8
}

/// A single frame of LiDAR point cloud data.
struct PointCloud {
    let timestamp: TimeInterval
    let points: [PackedPoint]
    var count: Int { points.count }
}

/// Complete capture frame: point cloud + camera metadata + RGB image.
struct CaptureFrame {
    let pointCloud: PointCloud
    let cameraTransform: simd_float4x4
    let viewMatrix: simd_float4x4
    let verticalFov: Float
    let cameraImage: CVPixelBuffer
    let orientation: UIInterfaceOrientation
    let depthResolution: (w: Int, h: Int)
    let imageResolution: (w: Int, h: Int)
}
