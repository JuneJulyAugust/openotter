import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let isPortrait = geo.size.height > geo.size.width
                let screenWidth = geo.size.width
                let screenHeight = geo.size.height

                let width = isPortrait ? screenHeight : screenWidth
                let height = isPortrait ? screenWidth : screenHeight

                HStack(spacing: 0) {
                    // LEFT: Branding
                    VStack(spacing: 16) {
                        // Logo mark
                        ZStack {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [Color(red: 0.04, green: 0.1, blue: 0.22),
                                             Color(red: 0.01, green: 0.03, blue: 0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 108, height: 108)
                                .shadow(color: .cyan.opacity(0.35), radius: 22, x: 0, y: 8)
                                .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)

                            Image(systemName: "steeringwheel")
                                .font(.system(size: 54, weight: .thin))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.cyan, Color(red: 0.2, green: 0.6, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }

                        VStack(spacing: 4) {
                            Text("OpenOtter")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            Text("autonomous ground robot")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                        }

                        let appVersion = Self.appVersion
                        Text("v\(appVersion)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .frame(width: width * 0.45)

                    // RIGHT: Actions
                    VStack(spacing: 20) {
                        NavigationLink(destination: SelfDrivingView()) {
                            actionCard(
                                title: "Self Driving",
                                subtitle: "Autonomous loop & planner",
                                icon: "steeringwheel",
                                color: .green
                            )
                        }

                        NavigationLink(destination: DiagnosticsView()) {
                            actionCard(
                                title: "Diagnostics",
                                subtitle: "Subsystem tools & tests",
                                icon: "wrench.and.screwdriver.fill",
                                color: .orange
                            )
                        }
                    }
                    .frame(width: width * 0.45)
                    .padding(.trailing, 40)
                }
                .frame(width: width, height: height)
                .background(Color(.systemGroupedBackground))
                .rotationEffect(isPortrait ? .degrees(90) : .degrees(0))
                .position(x: screenWidth / 2, y: screenHeight / 2)
            }
            .ignoresSafeArea()
            .navigationTitle("OpenOtter")
            .navigationBarHidden(true)
        }
    }

    /// Read version from the bundled VERSION file (single source of truth),
    /// with Info.plist fallback.
    private static var appVersion: String {
        if let url = Bundle.main.url(forResource: "VERSION", withExtension: nil),
           let text = try? String(contentsOf: url).trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        let plist = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return plist.isEmpty ? "Unknown" : plist
    }

    private func actionCard(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(color)
                .cornerRadius(16)
                .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.subheadline.bold())
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.07), radius: 12, x: 0, y: 6)
    }
}

// MARK: - DiagnosticsView

struct DiagnosticsView: View {
    var body: some View {
        List {
            Section("Perception") {
                diagRow(
                    title: "LiDAR Capture",
                    subtitle: "3D point cloud visualization",
                    icon: "cube.transparent",
                    color: .cyan,
                    destination: DepthCaptureView()
                )
            }

            Section("Estimation") {
                diagRow(
                    title: "ARKit 6D Pose",
                    subtitle: "Real-time pose & map tracking",
                    icon: "move.3d",
                    color: .purple,
                    destination: ARKitPoseView()
                )
            }

            Section("Control") {
                diagRow(
                    title: "STM32 Direct BLE",
                    subtitle: "PWM control via Bluetooth",
                    icon: "bolt.horizontal.fill",
                    color: .blue,
                    destination: STM32ControlView()
                )
                diagRow(
                    title: "Raspberry Pi WiFi",
                    subtitle: "MCP bridge over UDP",
                    icon: "cpu",
                    color: .orange,
                    destination: RaspberryPiControlView()
                )
            }

            Section("Agent") {
                diagRow(
                    title: "Agent Diagnostics",
                    subtitle: "Telegram bot & command pipeline",
                    icon: "bubble.left.and.bubble.right.fill",
                    color: .teal,
                    destination: AgentDebugView()
                )
            }
        }
        .navigationTitle("Diagnostics")
    }

    private func diagRow<D: View>(title: String, subtitle: String, icon: String, color: Color, destination: D) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(color)
                    .cornerRadius(9)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.bold())
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }
}
