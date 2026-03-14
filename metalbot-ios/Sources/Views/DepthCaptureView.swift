import SwiftUI

/// Main view: LiDAR point cloud capture with RGB camera preview.
/// Portrait: RGB top, point cloud bottom.
/// Landscape: RGB left, point cloud right.
struct DepthCaptureView: View {
    @StateObject private var viewModel = CaptureViewModel()
    @Environment(\.horizontalSizeClass) var hSizeClass

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.state {
            case .idle:
                startPrompt
            case .requesting:
                ProgressView("Starting capture...")
                    .foregroundStyle(.white)
            case .running:
                captureDisplay
            case .error(let message):
                errorDisplay(message)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(viewModel.state == .running)
    }

    private var captureDisplay: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            ZStack {
                if isLandscape {
                    HStack(spacing: 0) {
                        cameraPreview
                        pointCloudPanel
                    }
                } else {
                    VStack(spacing: 0) {
                        cameraPreview
                        pointCloudPanel
                    }
                }

                VStack {
                    HStack {
                        DiagnosticsHUD(diagnostics: viewModel.diagnostics)
                            .padding(.top, isLandscape ? 8 : 50)
                            .padding(.leading, 12)
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        viewModeIndicator
                            .padding(.leading, 16)
                        Spacer()
                        Button(action: { viewModel.stopCapture() }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.red)
                        }
                        .padding(16)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private var cameraPreview: some View {
        Group {
            if let image = viewModel.cameraImage {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Color.black
            }
        }
    }

    private var pointCloudPanel: some View {
        PointCloudMTKView(renderer: viewModel.renderer)
    }

    @ViewBuilder
    private var viewModeIndicator: some View {
        let mode = viewModel.renderer.viewMode
        let label = mode == .cameraPOV ? "Camera POV" : "Orbit"
        let icon = mode == .cameraPOV ? "eye.fill" : "rotate.3d"

        Label(label, systemImage: icon)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var startPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 64))
                .foregroundStyle(.cyan)
            Text("metalbot")
                .font(.title.bold())
                .foregroundStyle(.white)
            Text("LiDAR Point Cloud")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: { viewModel.startCapture() }) {
                Label("Start Capture", systemImage: "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.cyan, in: Capsule())
                    .foregroundStyle(.black)
            }
        }
    }

    private func errorDisplay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
            Text("Capture Error")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: { viewModel.startCapture() }) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.cyan, in: Capsule())
                    .foregroundStyle(.black)
            }
        }
    }
}
