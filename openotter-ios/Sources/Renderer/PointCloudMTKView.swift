import SwiftUI
import MetalKit

/// SwiftUI wrapper around MTKView for point cloud rendering with orbit gestures.
struct PointCloudMTKView: UIViewRepresentable {
    let renderer: PointCloudRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = renderer.device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.delegate = renderer

        let pan = UIPanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }

    final class Coordinator: NSObject {
        let renderer: PointCloudRenderer
        private var lastPanLocation: CGPoint = .zero

        init(renderer: PointCloudRenderer) {
            self.renderer = renderer
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                renderer.enterOrbitMode()
                lastPanLocation = .zero
            }
            let location = gesture.translation(in: gesture.view)
            let dx = Float(location.x - lastPanLocation.x)
            let dy = Float(location.y - lastPanLocation.y)
            lastPanLocation = location

            renderer.orbitYaw += dx * 0.005
            renderer.orbitPitch = max(-.pi / 2 + 0.1, min(.pi / 2 - 0.1,
                renderer.orbitPitch - dy * 0.005))
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began {
                renderer.enterOrbitMode()
            }
            if gesture.state == .changed {
                renderer.orbitDistance = max(0.5, min(20,
                    renderer.orbitDistance / Float(gesture.scale)))
                gesture.scale = 1
            }
        }

        /// Double-tap to return to camera POV.
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            renderer.viewMode = .cameraPOV
        }
    }
}
