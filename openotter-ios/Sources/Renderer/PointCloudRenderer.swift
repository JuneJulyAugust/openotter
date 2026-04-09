import Foundation
import Metal
import MetalKit
import simd

/// Renders a PointCloud using Metal point primitives.
/// Supports camera-POV (default) and orbit viewing modes.
final class PointCloudRenderer: NSObject, MTKViewDelegate {
    enum RendererError: LocalizedError {
        case metalUnavailable
        case commandQueueUnavailable
        case shaderFunctionsUnavailable
        case pipelineCreationFailed(Error)
        case depthStateUnavailable
        case vertexBufferUnavailable

        var errorDescription: String? {
            switch self {
            case .metalUnavailable:
                return "Metal is not supported on this device."
            case .commandQueueUnavailable:
                return "Failed to create the Metal command queue."
            case .shaderFunctionsUnavailable:
                return "Failed to load Metal shader functions."
            case .pipelineCreationFailed(let error):
                return "Failed to build the Metal render pipeline: \(error.localizedDescription)"
            case .depthStateUnavailable:
                return "Failed to create Metal depth state."
            case .vertexBufferUnavailable:
                return "Failed to allocate Metal vertex buffer."
            }
        }
    }

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let vertexBuffer: MTLBuffer

    private var pointCount: Int = 0
    private static let maxPoints = 256 * 192
    private let stateLock = NSLock()

    // Camera data from ARKit (orientation-aware)
    private var cameraTransform: simd_float4x4 = matrix_identity_float4x4
    private var viewMatrix: simd_float4x4 = matrix_identity_float4x4
    private var verticalFov: Float = 1.0

    // View mode
    enum ViewMode { case cameraPOV, orbit }
    private var _viewMode: ViewMode = .cameraPOV
    var viewMode: ViewMode {
        get { stateLock.sync { _viewMode } }
        set { stateLock.sync { _viewMode = newValue } }
    }

    // Orbit parameters
    private var _orbitYaw: Float = 0
    private var _orbitPitch: Float = 0
    private var _orbitDistance: Float = 3.0
    private var _orbitCenter: SIMD3<Float> = .zero

    var orbitYaw: Float {
        get { stateLock.sync { _orbitYaw } }
        set { stateLock.sync { _orbitYaw = newValue } }
    }

    var orbitPitch: Float {
        get { stateLock.sync { _orbitPitch } }
        set { stateLock.sync { _orbitPitch = newValue } }
    }

    var orbitDistance: Float {
        get { stateLock.sync { _orbitDistance } }
        set { stateLock.sync { _orbitDistance = newValue } }
    }

    var orbitCenter: SIMD3<Float> {
        get { stateLock.sync { _orbitCenter } }
        set { stateLock.sync { _orbitCenter = newValue } }
    }

    private var _pointSize: Float = 4.0
    var pointSize: Float {
        get { stateLock.sync { _pointSize } }
        set { stateLock.sync { _pointSize = max(newValue, 1.0) } }
    }

    private struct Uniforms {
        var viewProjection: simd_float4x4
        var pointSize: Float
    }

    private struct RenderSnapshot {
        let pointCount: Int
        let viewMatrix: simd_float4x4
        let verticalFov: Float
        let viewMode: ViewMode
        let orbitYaw: Float
        let orbitPitch: Float
        let orbitDistance: Float
        let orbitCenter: SIMD3<Float>
        let pointSize: Float
    }

    static func make() throws -> PointCloudRenderer {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.metalUnavailable
        }

        guard let queue = device.makeCommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }

        guard let library = device.makeDefaultLibrary(),
              let vertFunc = library.makeFunction(name: "pointVertex"),
              let fragFunc = library.makeFunction(name: "pointFragment") else {
            throw RendererError.shaderFunctionsUnavailable
        }

        let vertDesc = MTLVertexDescriptor()
        vertDesc.attributes[0].format = .float3
        vertDesc.attributes[0].offset = 0
        vertDesc.attributes[0].bufferIndex = 0
        vertDesc.attributes[1].format = .uchar4
        vertDesc.attributes[1].offset = MemoryLayout<SIMD3<Float>>.size
        vertDesc.attributes[1].bufferIndex = 0
        vertDesc.layouts[0].stride = MemoryLayout<PackedPoint>.stride
        vertDesc.layouts[0].stepRate = 1

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.vertexFunction = vertFunc
        pipeDesc.fragmentFunction = fragFunc
        pipeDesc.vertexDescriptor = vertDesc
        pipeDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeDesc.depthAttachmentPixelFormat = .depth32Float

        let pipelineState: MTLRenderPipelineState
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipeDesc)
        } catch {
            throw RendererError.pipelineCreationFailed(error)
        }

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDesc) else {
            throw RendererError.depthStateUnavailable
        }

        guard let vertexBuffer = device.makeBuffer(
            length: Self.maxPoints * MemoryLayout<PackedPoint>.stride,
            options: .storageModeShared
        ) else {
            throw RendererError.vertexBufferUnavailable
        }

        return PointCloudRenderer(
            device: device,
            commandQueue: queue,
            pipelineState: pipelineState,
            depthState: depthState,
            vertexBuffer: vertexBuffer
        )
    }

    private init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipelineState: MTLRenderPipelineState,
        depthState: MTLDepthStencilState,
        vertexBuffer: MTLBuffer
    ) {
        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        self.depthState = depthState
        self.vertexBuffer = vertexBuffer

        super.init()
    }

    /// Upload new point cloud and camera state.
    func update(
        cloud: PointCloud,
        cameraTransform: simd_float4x4,
        viewMatrix: simd_float4x4,
        verticalFov: Float
    ) {
        let count = min(cloud.count, Self.maxPoints)
        if count > 0 {
            let dest = vertexBuffer.contents().assumingMemoryBound(to: PackedPoint.self)
            cloud.points.withUnsafeBufferPointer { source in
                guard let baseAddress = source.baseAddress else { return }
                dest.update(from: baseAddress, count: count)
            }
        }

        let fallbackCentroid = count > 0 ? computeFallbackCentroid(points: cloud.points, count: count) : nil

        stateLock.sync {
            pointCount = count
            self.cameraTransform = cameraTransform
            self.viewMatrix = viewMatrix
            self.verticalFov = verticalFov.isFinite && verticalFov > .ulpOfOne
                ? verticalFov
                : Float.pi / 3

            if let centroid = cloud.centroid ?? fallbackCentroid {
                _orbitCenter = centroid
            }
        }
    }

    /// Transition from camera POV to orbit, starting from current camera position.
    func enterOrbitMode() {
        stateLock.sync {
            guard _viewMode == .cameraPOV else { return }
            _viewMode = .orbit

            let cameraPosition = SIMD3<Float>(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            )
            let delta = cameraPosition - _orbitCenter
            let distance = max(length(delta), 0.001)

            _orbitDistance = distance
            _orbitYaw = atan2(delta.x, delta.z)
            let normalizedY = max(-1.0, min(1.0, delta.y / distance))
            _orbitPitch = asin(normalizedY)
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let snapshot = stateLock.sync {
            RenderSnapshot(
                pointCount: pointCount,
                viewMatrix: viewMatrix,
                verticalFov: verticalFov,
                viewMode: _viewMode,
                orbitYaw: _orbitYaw,
                orbitPitch: _orbitPitch,
                orbitDistance: _orbitDistance,
                orbitCenter: _orbitCenter,
                pointSize: _pointSize
            )
        }

        guard snapshot.pointCount > 0,
              view.drawableSize.height > 0,
              let drawable = view.currentDrawable,
              let passDesc = view.currentRenderPassDescriptor,
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            return
        }

        let aspect = Float(view.drawableSize.width / view.drawableSize.height)
        let proj = perspectiveMatrix(fovY: snapshot.verticalFov, aspect: aspect, near: 0.01, far: 50)

        let viewMat: simd_float4x4
        switch snapshot.viewMode {
        case .cameraPOV:
            viewMat = snapshot.viewMatrix
        case .orbit:
            viewMat = orbitViewMatrix(snapshot: snapshot)
        }

        var uniforms = Uniforms(viewProjection: proj * viewMat, pointSize: snapshot.pointSize)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: snapshot.pointCount)
        encoder.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: - Orbit camera

    private func orbitViewMatrix(snapshot: RenderSnapshot) -> simd_float4x4 {
        let cy = cos(snapshot.orbitYaw)
        let sy = sin(snapshot.orbitYaw)
        let cp = cos(snapshot.orbitPitch)
        let sp = sin(snapshot.orbitPitch)

        let eye = snapshot.orbitCenter + SIMD3<Float>(
            snapshot.orbitDistance * cp * sy,
            snapshot.orbitDistance * sp,
            snapshot.orbitDistance * cp * cy
        )

        return lookAt(eye: eye, center: snapshot.orbitCenter, up: SIMD3<Float>(0, 1, 0))
    }

    private func computeFallbackCentroid(points: [PackedPoint], count: Int) -> SIMD3<Float>? {
        guard count > 0 else { return nil }

        var sum = SIMD3<Float>.zero
        for index in 0..<count {
            sum += points[index].position
        }

        return sum / Float(count)
    }
}

// MARK: - Matrix helpers

private func perspectiveMatrix(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    guard aspect.isFinite, aspect > .ulpOfOne else { return matrix_identity_float4x4 }

    let sy = 1.0 / tan(fovY * 0.5)
    let sx = sy / aspect
    let zRange = far - near

    return simd_float4x4(columns: (
        SIMD4<Float>(sx, 0, 0, 0),
        SIMD4<Float>(0, sy, 0, 0),
        SIMD4<Float>(0, 0, -(far + near) / zRange, -1),
        SIMD4<Float>(0, 0, -2 * far * near / zRange, 0)
    ))
}

private func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
    let f = normalize(center - eye)
    let s = normalize(cross(f, up))
    let u = cross(s, f)

    return simd_float4x4(columns: (
        SIMD4<Float>(s.x, u.x, -f.x, 0),
        SIMD4<Float>(s.y, u.y, -f.y, 0),
        SIMD4<Float>(s.z, u.z, -f.z, 0),
        SIMD4<Float>(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)
    ))
}

private extension NSLock {
    func sync<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
