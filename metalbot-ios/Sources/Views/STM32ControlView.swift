import SwiftUI

struct STM32ControlView: View {
    @StateObject var viewModel = STM32ControlViewModel()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {

                    // --- CONNECTION STATUS ---
                    GroupBox(label:
                        Label("BLE CONNECTION", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 10, height: 10)
                                Text(viewModel.status.rawValue)
                                    .font(.subheadline.bold())
                                    .foregroundColor(statusColor)
                                Spacer()
                                if viewModel.status != .connected {
                                    Button(action: { viewModel.reconnect() }) {
                                        Image(systemName: "arrow.clockwise.circle.fill")
                                            .font(.title3)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }

                            if viewModel.status == .connected {
                                HStack(spacing: 24) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Device").font(.caption2).foregroundStyle(.secondary)
                                        Text(viewModel.deviceName)
                                            .font(.caption.bold().monospaced())
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("RSSI").font(.caption2).foregroundStyle(.secondary)
                                        Text("\(viewModel.rssi) dBm")
                                            .font(.caption.bold().monospacedDigit())
                                    }
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Sent").font(.caption2).foregroundStyle(.secondary)
                                        Text("\(viewModel.commandsSent)")
                                            .font(.caption.bold().monospacedDigit())
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // --- CONTROL SLIDERS ---
                    GroupBox(label:
                        Label("DIRECT CONTROL", systemImage: "gamecontroller.fill")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    ) {
                        VStack(spacing: 24) {
                            ControlSlider(
                                label: "Steering",
                                icon: "steeringwheel",
                                value: $viewModel.steering,
                                color: .cyan,
                                onUpdate: { viewModel.updateSteering($0) }
                            )

                            ControlSlider(
                                label: "Throttle",
                                icon: "engine.combustion.fill",
                                value: $viewModel.throttle,
                                color: .mint,
                                onUpdate: { viewModel.updateThrottle($0) }
                            )

                            // PWM readout
                            HStack {
                                VStack(spacing: 2) {
                                    Text("Steering PWM")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(steeringPWM) µs")
                                        .font(.system(.caption, design: .monospaced).bold())
                                        .foregroundColor(.cyan)
                                }
                                Spacer()
                                VStack(spacing: 2) {
                                    Text("Throttle PWM")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(throttlePWM) µs")
                                        .font(.system(.caption, design: .monospaced).bold())
                                        .foregroundColor(.mint)
                                }
                            }
                            .padding(.horizontal)

                            Button(action: { viewModel.resetToNeutral() }) {
                                Label("NEUTRAL / RESET", systemImage: "poweroff")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .foregroundColor(.red)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.red, lineWidth: 2)
                                    )
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .opacity(viewModel.status == .connected ? 1.0 : 0.4)
                    .disabled(viewModel.status != .connected)

                    // --- VERSION INFO ---
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("STM32 MCP v0.2.0-ble")
                            Spacer()
                            Text("Direct BLE Control")
                        }
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)

                        Text("Bypass Raspberry Pi — iPhone → STM32 → PWM")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("STM32 Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        switch viewModel.status {
        case .connected: return .green
        case .scanning, .connecting, .discovering: return .orange
        case .disconnected, .unauthorized, .poweredOff: return .red
        }
    }

    /// Convert normalized steering [-1, +1] to PWM µs for display
    private var steeringPWM: Int {
        Int(1500.0 + viewModel.steering * 500.0)
    }

    /// Convert normalized throttle [-1, +1] to PWM µs for display
    private var throttlePWM: Int {
        Int(1500.0 + viewModel.throttle * 500.0)
    }
}
