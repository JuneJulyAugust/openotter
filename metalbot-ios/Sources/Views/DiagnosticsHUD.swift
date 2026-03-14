import SwiftUI

/// Overlay HUD showing real-time capture diagnostics.
struct DiagnosticsHUD: View {
    let diagnostics: FrameDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("FPS", String(format: "%.1f", diagnostics.fps))
            row("PTS", "\(diagnostics.pointCount)")
            row("DEPTH", diagnostics.depthResolution)
            row("IMAGE", diagnostics.imageResolution)
            row("VFOV", String(format: "%.1f°", diagnostics.fovDeg))
            row("VIEW", diagnostics.viewMode)
            row("CAM", "LiDAR (back)")
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
            Text(value)
                .foregroundStyle(.primary)
        }
    }
}
