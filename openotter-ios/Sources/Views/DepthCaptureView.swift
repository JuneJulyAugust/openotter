import SwiftUI

/// Main view: LiDAR point cloud capture with RGB camera preview.
/// Portrait: RGB top, point cloud bottom.
/// Landscape: RGB left, point cloud right.
struct DepthCaptureView: View {
    @StateObject private var viewModel = CaptureViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.state {
            case .idle, .requesting:
                ProgressView("Starting capture…")
                    .foregroundStyle(.white)
            case .running:
                captureDisplay
            case .error(let message):
                errorDisplay(message)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(viewModel.state == .running)
        .onAppear { viewModel.startCapture() }
        .onDisappear { viewModel.stopCapture() }
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
                        Button(action: {
                            viewModel.stopCapture()
                            dismiss()
                        }) {
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
        Group {
            if let renderer = viewModel.renderer {
                PointCloudMTKView(renderer: renderer)
            } else {
                ZStack {
                    Color.black
                    Text("Renderer unavailable")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var viewModeIndicator: some View {
        if let renderer = viewModel.renderer {
            let mode = renderer.viewMode
            let label = mode == .cameraPOV ? "Camera POV" : "Orbit"
            let icon = mode == .cameraPOV ? "eye.fill" : "rotate.3d"

            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
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
