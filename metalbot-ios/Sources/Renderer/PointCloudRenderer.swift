import Metal
import MetalKit
import simd

/// Renders a PointCloud using Metal point primitives.
/// Supports camera-POV (default) and orbit viewing modes.
final class PointCloudRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    private var vertexBuffer: MTLBuffer?
    private var pointCount: Int = 0
    private let maxPoints = 256 * 192

    // Camera data from ARKit (orientation-aware)
    private var cameraTransform: simd_float4x4 = matrix_identity_float4x4
    private var viewMatrix: simd_float4x4 = matrix_identity_float4x4
    private var verticalFov: Float = 1.0

    // View mode
    enum ViewMode { case cameraPOV, orbit }
    var viewMode: ViewMode = .cameraPOV

    // Orbit parameters
    var orbitYaw: Float = 0
    var orbitPitch: Float = 0
    var orbitDistance: Float = 3.0
    var orbitCenter: SIMD3<Float> = .zero

    var pointSize: Float = 4.0

    private struct Uniforms {
        var viewProjection: simd_float4x4
        var pointSize: Float
    }

    override init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary(),
              let vertFunc = library.makeFunction(name: "pointVertex"),
              let fragFunc = library.makeFunction(name: "pointFragment") else {
            fatalError("Failed to load Metal shaders")
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

        self.pipelineState = try! device.makeRenderPipelineState(descriptor: pipeDesc)

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        self.depthState = device.makeDepthStencilState(descriptor: depthDesc)!

        self.vertexBuffer = device.makeBuffer(
            length: maxPoints * MemoryLayout<PackedPoint>.stride,
            options: .storageModeShared
        )

        super.init()
    }

    /// Upload new point cloud and camera state.
    func update(
        cloud: PointCloud,
        cameraTransform: simd_float4x4,
        viewMatrix: simd_float4x4,
        verticalFov: Float
    ) {
        let count = min(cloud.count, maxPoints)
        guard count > 0, let buffer = vertexBuffer else { return }

        let dest = buffer.contents().assumingMemoryBound(to: PackedPoint.self)
        cloud.points.withUnsafeBufferPointer { src in
            dest.update(from: src.baseAddress!, count: count)
        }
        pointCount = count

        self.cameraTransform = cameraTransform
        self.viewMatrix = viewMatrix
        self.verticalFov = verticalFov

        // Update orbit center to centroid
        var sum = SIMD3<Float>.zero
        for i in 0..<count {
            sum += cloud.points[i].position
        }
        orbitCenter = sum / Float(count)
    }

    /// Transition from camera POV to orbit, starting from current camera position.
    func enterOrbitMode() {
        guard viewMode == .cameraPOV else { return }
        viewMode = .orbit

        let camPos = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        let delta = camPos - orbitCenter
        orbitDistance = length(delta)
        orbitYaw = atan2(delta.x, delta.z)
        orbitPitch = asin(delta.y / max(orbitDistance, 0.001))
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard pointCount > 0,
              let drawable = view.currentDrawable,
              let passDesc = view.currentRenderPassDescriptor,
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            return
        }

        let aspect = Float(view.drawableSize.width / view.drawableSize.height)
        let proj = perspectiveMatrix(fovY: verticalFov, aspect: aspect, near: 0.01, far: 50)

        let viewMat: simd_float4x4
        switch viewMode {
        case .cameraPOV:
            viewMat = viewMatrix
        case .orbit:
            viewMat = orbitViewMatrix()
        }

        var uniforms = Uniforms(viewProjection: proj * viewMat, pointSize: pointSize)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointCount)
        encoder.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: - Orbit camera

    private func orbitViewMatrix() -> simd_float4x4 {
        let cy = cos(orbitYaw), sy = sin(orbitYaw)
        let cp = cos(orbitPitch), sp = sin(orbitPitch)

        let eye = orbitCenter + SIMD3<Float>(
            orbitDistance * cp * sy,
            orbitDistance * sp,
            orbitDistance * cp * cy
        )

        return lookAt(eye: eye, center: orbitCenter, up: SIMD3<Float>(0, 1, 0))
    }
}

// MARK: - Matrix helpers

private func perspectiveMatrix(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
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
