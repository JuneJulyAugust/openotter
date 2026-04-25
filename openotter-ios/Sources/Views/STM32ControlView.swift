import SwiftUI

/// Discrete values for steering/throttle: -1.0, -0.9, ..., 0.0, ..., 0.9, 1.0
private let discreteSteps: [Float] = stride(from: -1.0, through: 1.0, by: 0.1)
    .map { Float((round($0 * 10) / 10)) }

struct STM32ControlView: View {
    @StateObject var viewModel = STM32ControlViewModel()

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {

                    // --- VL53L5CX TOF DEBUG (FE60 multi-zone grid) ---
                    GroupBox(label:
                        Label("VL53L5CX DEPTH MAP", systemImage: "square.grid.3x3.fill")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    ) {
                        TofDebugCard(viewModel: viewModel)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

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

            }
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

    @State private var frequencyHz: Double = 10
    @State private var integrationMs: Double = 20

    private var maxRangeMm: UInt16 {
        4000
    }

    private var maxFrequencyHz: Double {
        Double(TofConfig.bleCapFrequencyHz(layout: viewModel.tofConfig.layout))
    }

    private var maxIntegrationMs: Double {
        Double(TofConfig.maxL5IntegrationMs(frequencyHz: viewModel.tofConfig.frequencyHz))
    }

    private var errorBanner: String {
        switch viewModel.tofLastError {
        case 0:  return ""
        case 1:  return "VL53L5CX not detected"
        case 2:  return "VL53L5CX boot failed"
        case 3:  return "VL53L5CX I2C error"
        case 4:  return "Firmware rejected VL53L5CX config"
        case 5:  return "VL53L5CX driver missing"
        case 6:  return "Firmware rejected layout"
        case 7:  return "Firmware rejected distance mode"
        case 8:  return "Budget below sensor minimum for this combo"
        case 9:  return "Driver rejected combo — rolled back to previous"
        case 10: return "ToF driver offline — reboot the board"
        default: return "ToF error \(viewModel.tofLastError)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Layout", selection: layoutBinding) {
                Text("4×4").tag(UInt8(4))
                Text("8×8").tag(UInt8(8))
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Rate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $frequencyHz, in: 1...maxFrequencyHz, step: 1)
                    .onChange(of: frequencyHz) { new in
                        viewModel.setTofFrequencyHz(UInt8(new))
                    }
                Text("\(Int(frequencyHz)) Hz")
                    .font(.caption.monospaced())
                    .frame(width: 60, alignment: .trailing)
            }

            HStack {
                Text("Integration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $integrationMs, in: 2...maxIntegrationMs, step: 1)
                    .onChange(of: integrationMs) { new in
                        viewModel.setTofIntegrationMs(UInt16(new))
                    }
                Text("\(Int(integrationMs)) ms")
                    .font(.caption.monospaced())
                    .frame(width: 60, alignment: .trailing)
            }

            HStack {
                Text("\(viewModel.tofConfig.layout)x\(viewModel.tofConfig.layout) target")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.tofState == .running ? "running" : "\(viewModel.tofState)")
                    .font(.caption2.monospaced())
                    .foregroundColor(viewModel.tofState == .running ? .green : .orange)
            }

            if !errorBanner.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorBanner)
                }
                .font(.caption2.bold())
                .foregroundColor(.orange)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
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

            VStack(alignment: .leading, spacing: 2) {
                Text("DEBUG")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(verbatim: "chunks rx \(viewModel.tofChunksReceived)  parsed \(viewModel.tofFramesParsed)  dropped \(viewModel.tofDroppedFrameChunks)")
                Text(verbatim: "state \(String(describing: viewModel.tofState))  err \(viewModel.tofLastError)  mode \(String(describing: viewModel.firmwareMode))")
                Text(verbatim: "sensor \(String(describing: viewModel.tofConfig.sensor))  layout \(viewModel.tofConfig.layout)x\(viewModel.tofConfig.layout)  freq \(viewModel.tofConfig.frequencyHz)Hz  it \(viewModel.tofConfig.integrationMs)ms")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(6)
        }
        .padding(.vertical, 4)
        .onAppear {
            frequencyHz = Double(viewModel.tofConfig.frequencyHz)
            integrationMs = Double(viewModel.tofConfig.integrationMs)
        }
        .onChange(of: viewModel.tofConfig.frequencyHz) { newHz in
            let value = Double(newHz)
            if abs(frequencyHz - value) > 0.5 { frequencyHz = value }
        }
        .onChange(of: viewModel.tofConfig.integrationMs) { newMs in
            let value = Double(newMs)
            if abs(integrationMs - value) > 0.5 { integrationMs = value }
        }
    }

    private var layoutBinding: Binding<UInt8> {
        Binding(get: { viewModel.tofConfig.layout },
                set: { viewModel.setTofLayout($0) })
    }

}
