import SwiftUI

struct MCPTestView: View {
    @StateObject var viewModel = MCPTestViewModel()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // --- DEVICE INFO ---
                    HStack(spacing: 12) {
                        DeviceMiniCard(name: viewModel.iphoneName, ip: viewModel.iphoneIP, icon: "brain.head.profile", color: .purple, label: "LOCAL (Brain)")
                        Image(systemName: "arrow.left.and.right")
                            .foregroundStyle(.secondary)
                        DeviceMiniCard(name: "metalbot-mcp", ip: "192.168.2.189", icon: "cpu", color: .blue, label: "REMOTE (MCP)")
                    }
                    .padding(.horizontal)

                    // --- CONNECTION CARD ---
                    GroupBox(label: 
                        Label("NETWORK METRICS", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    ) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Circle()
                                    .fill(viewModel.connectionStatus == "Connected" ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                
                                Text(viewModel.connectionStatus)
                                    .font(.subheadline.bold())
                                    .foregroundColor(viewModel.connectionStatus == "Connected" ? .green : .red)
                                Spacer()
                                Text("Last Rx: \(viewModel.lastReceivedTime)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            
                            Divider()
                            
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("IPHONE TX")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.blue)
                                    MetricRow(label: "Heartbeats", value: "\(viewModel.hbSentCount)")
                                    MetricRow(label: "Commands", value: "\(viewModel.cmdSentCount)")
                                }
                                Spacer()
                                Divider().frame(height: 40)
                                Spacer()
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("PI RX")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.green)
                                    MetricRow(label: "Heartbeats", value: "\(viewModel.hbReceivedCount)")
                                }
                            }
                        }
                        .padding(.vertical, 4)
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
                                    MetricRow(label: "Motor Speed", value: "\(viewModel.escTelemetry?.rpm ?? 0) RPM")
                                    MetricRow(label: "Voltage", value: String(format: "%.2f V", viewModel.escTelemetry?.voltage ?? 0.0))
                                }
                                Spacer()
                                Divider().frame(height: 40)
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

                    // --- CONTROL CARD ---
                    GroupBox(label: 
                        Label("MANUAL CONTROL", systemImage: "gamecontroller.fill")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    ) {
                        VStack(spacing: 24) {
                            ControlSlider(
                                label: "Steering",
                                icon: "steeringwheel",
                                value: $viewModel.steering,
                                color: .yellow,
                                onUpdate: { viewModel.updateSteering($0) }
                            )
                            
                            ControlSlider(
                                label: "Motor Power",
                                icon: "engine.combustion.fill",
                                value: $viewModel.motor,
                                color: .orange,
                                onUpdate: { viewModel.updateMotor($0) }
                            )
                            
                            Button(action: {
                                viewModel.updateSteering(0)
                                viewModel.updateMotor(0)
                            }) {
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

                    // --- SYSTEM INFO ---
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("iOS Brain v0.2.0")
                            Spacer()
                            Text("MCP Pi v0.1.0")
                        }
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("WHAT'S NEW (v0.2.0)")
                                .font(.caption.bold())
                            Text("• Bi-directional MCP bridge over UDP\n• Real-time network metrics and 1.5s timeout\n• New manual control dashboard with bi-directional meters")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("MCP Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .bold()
                }
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
