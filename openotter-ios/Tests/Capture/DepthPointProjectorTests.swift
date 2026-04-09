import CoreVideo
import simd
import XCTest
@testable import openotter

final class DepthPointProjectorTests: XCTestCase {
    private let epsilon: Float = 1e-4

    func testBackProjectionMatchesCameraModel() throws {
        let depthMap = try makeDepthMap(width: 2, height: 2, values: [
            0.0, 2.0,
            0.0, 0.0
        ])
        let intrinsics = makeIntrinsics(fx: 2.0, fy: 2.0, cx: 0.5, cy: 0.5)
        let projector = DepthPointProjector(colorRangeMeters: 5.0)

        let result = projector.project(
            depthMap: depthMap,
            confidenceMap: nil,
            intrinsics: intrinsics,
            imageResolution: CGSize(width: 2, height: 2),
            cameraTransform: matrix_identity_float4x4
        )

        XCTAssertEqual(result.points.count, 1)
        let point = try XCTUnwrap(result.points.first)
        XCTAssertApproximatelyEqual(point.position.x, 0.5, accuracy: epsilon)
        XCTAssertApproximatelyEqual(point.position.y, 0.5, accuracy: epsilon)
        XCTAssertApproximatelyEqual(point.position.z, -2.0, accuracy: epsilon)

        let centroid = try XCTUnwrap(result.centroid)
        XCTAssertApproximatelyEqual(centroid.x, point.position.x, accuracy: epsilon)
        XCTAssertApproximatelyEqual(centroid.y, point.position.y, accuracy: epsilon)
        XCTAssertApproximatelyEqual(centroid.z, point.position.z, accuracy: epsilon)
    }

    func testIntrinsicsAreScaledToDepthResolution() throws {
        let depthMap = try makeDepthMap(width: 2, height: 2, values: [
            0.0, 0.0,
            0.0, 2.0
        ])
        let intrinsicsAtImageResolution = makeIntrinsics(fx: 4.0, fy: 4.0, cx: 2.0, cy: 2.0)
        let projector = DepthPointProjector(colorRangeMeters: 5.0)

        let result = projector.project(
            depthMap: depthMap,
            confidenceMap: nil,
            intrinsics: intrinsicsAtImageResolution,
            imageResolution: CGSize(width: 4, height: 4),
            cameraTransform: matrix_identity_float4x4
        )

        XCTAssertEqual(result.points.count, 1)
        let point = try XCTUnwrap(result.points.first)
        XCTAssertApproximatelyEqual(point.position.x, 0.0, accuracy: epsilon)
        XCTAssertApproximatelyEqual(point.position.y, 0.0, accuracy: epsilon)
        XCTAssertApproximatelyEqual(point.position.z, -2.0, accuracy: epsilon)
    }

    func testConfidenceMapFiltersOutZeroConfidencePixels() throws {
        let depthMap = try makeDepthMap(width: 2, height: 1, values: [1.0, 1.5])
        let confidenceMap = try makeConfidenceMap(width: 2, height: 1, values: [0, 2])
        let intrinsics = makeIntrinsics(fx: 2.0, fy: 2.0, cx: 0.5, cy: 0.0)
        let projector = DepthPointProjector(colorRangeMeters: 5.0)

        let result = projector.project(
            depthMap: depthMap,
            confidenceMap: confidenceMap,
            intrinsics: intrinsics,
            imageResolution: CGSize(width: 2, height: 1),
            cameraTransform: matrix_identity_float4x4
        )

        XCTAssertEqual(result.points.count, 1)
        let point = try XCTUnwrap(result.points.first)
        XCTAssertApproximatelyEqual(point.position.z, -1.5, accuracy: epsilon)
    }

    private func makeDepthMap(width: Int, height: Int, values: [Float]) throws -> CVPixelBuffer {
        XCTAssertEqual(values.count, width * height)

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixelBuffer)

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            XCTFail("Depth map base address is nil")
            return buffer
        }

        for row in 0..<height {
            let rowStart = baseAddress.advanced(by: row * bytesPerRow)
                .assumingMemoryBound(to: Float.self)
            for column in 0..<width {
                rowStart[column] = values[row * width + column]
            }
        }

        return buffer
    }

    private func makeConfidenceMap(width: Int, height: Int, values: [UInt8]) throws -> CVPixelBuffer {
        XCTAssertEqual(values.count, width * height)

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixelBuffer)

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            XCTFail("Confidence map base address is nil")
            return buffer
        }

        for row in 0..<height {
            let rowStart = baseAddress.advanced(by: row * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for column in 0..<width {
                rowStart[column] = values[row * width + column]
            }
        }

        return buffer
    }

    private func makeIntrinsics(fx: Float, fy: Float, cx: Float, cy: Float) -> simd_float3x3 {
        simd_float3x3(
            columns: (
                SIMD3<Float>(fx, 0.0, 0.0),
                SIMD3<Float>(0.0, fy, 0.0),
                SIMD3<Float>(cx, cy, 1.0)
            )
        )
    }

    private func XCTAssertApproximatelyEqual(
        _ lhs: Float,
        _ rhs: Float,
        accuracy: Float,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs, rhs, accuracy: accuracy, file: file, line: line)
    }
}
