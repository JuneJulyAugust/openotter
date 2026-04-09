import SwiftUI

/// Shared UI components for openotter-ios.

struct MetricRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.bold().monospacedDigit())
        }
    }
}

struct ControlSlider: View {
    let label: String
    let icon: String
    var value: Binding<Float>
    let color: Color
    let onUpdate: (Float) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(label)
                    .font(.subheadline.bold())
                Spacer()
                Text(String(format: "%.0f%%", value.wrappedValue * 100))
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundColor(color)
            }

            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { newValue in
                    value.wrappedValue = newValue
                    onUpdate(newValue)
                }
            ), in: -1.0...1.0)
            .tint(color)

            HStack {
                Text("-100").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("0").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("+100").font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

struct DeviceMiniCard: View {
    let name: String
    let ip: String
    let icon: String
    let color: Color
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(name)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
            }
            Text(ip)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
}

struct ModernGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
            configuration.content
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}
