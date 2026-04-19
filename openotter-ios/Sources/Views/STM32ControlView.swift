import SwiftUI

/// Discrete values for steering/throttle: -1.0, -0.9, ..., 0.0, ..., 0.9, 1.0
private let discreteSteps: [Float] = stride(from: -1.0, through: 1.0, by: 0.1)
    .map { Float((round($0 * 10) / 10)) }

struct STM32ControlView: View {
    @StateObject var viewModel = STM32ControlViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {

                    // --- ESC TELEMETRY CARD ---
                    GroupBox(label:
                        Label("ESC TELEMETRY (Direct BLE)", systemImage: "bolt.horizontal.fill")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    ) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Circle()
                                    .fill(viewModel.escStatus == .connected ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)

                                Text(viewModel.escStatus.rawValue)
                                    .font(.subheadline.bold())
                                    .foregroundColor(viewModel.escStatus == .connected ? .green : .orange)

                                if viewModel.escStatus == .connected {
                                    Text("(\(viewModel.escDeviceName))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if let telemetry = viewModel.escTelemetry {
                                    Text("\(String(format: "%.1f", telemetry.updateFrequency)) Hz")
                                        .font(.caption.monospacedDigit().bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                }
                            }

                            Divider()

                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 12) {
                                    MetricRow(label: "Motor Speed", value: String(format: "%.2f m/s", viewModel.escTelemetry?.speedMps ?? 0.0))
                                    MetricRow(label: "Motor RPM", value: "\(viewModel.escTelemetry?.rpm ?? 0)")
                                    MetricRow(label: "Voltage", value: String(format: "%.2f V", viewModel.escTelemetry?.voltage ?? 0.0))
                                }
                                Spacer()
                                Divider().frame(height: 60)
                                Spacer()
                                VStack(alignment: .leading, spacing: 12) {
                                    MetricRow(label: "ESC Temp", value: String(format: "%.1f °C", viewModel.escTelemetry?.escTemperature ?? 0.0))
                                    MetricRow(label: "Motor Temp", value: String(format: "%.1f °C", viewModel.escTelemetry?.motorTemperature ?? 0.0))
                                }
                            }

                            if let telemetry = viewModel.escTelemetry {
                                Text("Last update: \(telemetry.timestamp.formatted(date: .omitted, time: .complete)) • Messages: \(telemetry.messageCount)")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // --- TOF DEBUG (FE60 multi-zone grid) ---
                    GroupBox(label:
                        Label("TOF DEBUG", systemImage: "square.grid.3x3.fill")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    ) {
                        TofDebugCard(viewModel: viewModel)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                    .opacity(viewModel.status == .connected ? 1.0 : 0.4)
                    .disabled(viewModel.status != .connected)

                    // --- DIRECT CONTROL (Discrete Steps) ---
                    GroupBox(label:
                        Label("DIRECT CONTROL", systemImage: "gamecontroller.fill")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    ) {
                        VStack(spacing: 24) {
                            DiscreteControlPicker(
                                label: "Steering",
                                icon: "steeringwheel",
                                value: viewModel.steering,
                                color: .cyan,
                                onSelect: { viewModel.updateSteering($0) }
                            )

                            DiscreteControlPicker(
                                label: "Throttle",
                                icon: "engine.combustion.fill",
                                value: viewModel.throttle,
                                color: .mint,
                                onSelect: { viewModel.updateThrottle($0) }
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
                            Text("STM32 MCP v0.2.1")
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text("STM32 Control")
                            .font(.headline)
                        Text("· \(viewModel.status.rawValue)")
                            .font(.caption)
                            .foregroundColor(statusColor)
                    }
                }
                if viewModel.status != .connected {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { viewModel.reconnect() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
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

// MARK: - Discrete Control Picker

/// A picker that lets the user select from discrete values: -1.0, -0.9, ..., 0.0, ..., 0.9, 1.0
private struct DiscreteControlPicker: View {
    let label: String
    let icon: String
    let value: Float
    let color: Color
    let onSelect: (Float) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(label)
                    .font(.subheadline.bold())
                Spacer()
                Text(String(format: "%+.1f", value))
                    .font(.system(.title3, design: .monospaced).bold())
                    .foregroundColor(color)
            }

            Picker(label, selection: Binding(
                get: { roundedValue },
                set: { onSelect($0) }
            )) {
                ForEach(discreteSteps, id: \.self) { step in
                    Text(String(format: "%+.1f", step))
                        .tag(step)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 100)
        }
    }

    private var roundedValue: Float {
        let rounded = (value * 10).rounded() / 10
        return max(-1.0, min(1.0, rounded))
    }
}

// MARK: - ToF Debug Card

private struct TofDebugCard: View {
    @ObservedObject var viewModel: STM32ControlViewModel

    /// UI-side mirror of slider position (ms). Initialised from current cfg.
    @State private var budgetMs: Double = 33

    /// Hue cap (mm) inferred from distance mode — keeps the heat map readable
    /// regardless of the configured distance ceiling.
    private var maxRangeMm: UInt16 {
        switch viewModel.tofConfig.distMode {
        case 1:  return 1300
        case 2:  return 2900
        default: return 3600
        }
    }

    /// Coarse Hz prediction: 1 / (zones × budget). Not a guarantee — actual
    /// rate is reported by the firmware in tofScanHz.
    private var predictedHz: Int {
        let zones = max(1, Int(viewModel.tofConfig.layout) * Int(viewModel.tofConfig.layout))
        let budgetSec = Double(viewModel.tofConfig.budgetUs) / 1_000_000.0
        let total = budgetSec * Double(zones)
        return total > 0 ? Int((1.0 / total).rounded()) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Layout", selection: layoutBinding) {
                Text("1×1").tag(UInt8(1))
                Text("3×3").tag(UInt8(3))
                Text("4×4").tag(UInt8(4))
            }
            .pickerStyle(.segmented)

            Picker("Distance", selection: distModeBinding) {
                Text("Short").tag(UInt8(1))
                Text("Medium").tag(UInt8(2))
                Text("Long").tag(UInt8(3))
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Budget")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $budgetMs, in: 8...200, step: 1)
                    .onChange(of: budgetMs) { new in
                        viewModel.setTofBudgetMs(UInt32(new))
                    }
                Text("\(Int(budgetMs)) ms")
                    .font(.caption.monospaced())
                    .frame(width: 60, alignment: .trailing)
            }

            HStack {
                Text("≈ \(predictedHz) Hz expected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.tofState == .running ? "running" : "\(viewModel.tofState)")
                    .font(.caption2.monospaced())
                    .foregroundColor(viewModel.tofState == .running ? .green : .orange)
            }

            if let f = viewModel.tofFrame {
                TofGridView(frame: f, maxRangeMm: maxRangeMm)
                    .padding(.vertical, 4)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 120)
                    .overlay(Text("Waiting for frame…").foregroundStyle(.secondary))
            }

            HStack {
                Text("seq \(viewModel.tofFrame?.seq ?? 0)")
                Spacer()
                Text("\(viewModel.tofScanHz) Hz")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .onAppear {
            budgetMs = Double(viewModel.tofConfig.budgetUs) / 1000.0
        }
    }

    private var layoutBinding: Binding<UInt8> {
        Binding(get: { viewModel.tofConfig.layout },
                set: { viewModel.setTofLayout($0) })
    }

    private var distModeBinding: Binding<UInt8> {
        Binding(get: { viewModel.tofConfig.distMode },
                set: { viewModel.setTofDistMode($0) })
    }
}
