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
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 120, height: 120)
                                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                            
                            Image(systemName: "sensor.tag.radiowaves.forward")
                                .font(.system(size: 50, weight: .light))
                                .foregroundColor(.cyan)
                        }
                        
                        Text("metalbot")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        
                        Text("v0.6.0")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .frame(width: width * 0.45)
                    
                    // RIGHT: Actions
                    VStack(spacing: 24) {
                        NavigationLink(destination: SelfDrivingView()) {
                            actionCard(
                                title: "Self Driving",
                                subtitle: "Autonomous loop & Planner",
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
            .navigationBarHidden(true)
        }
    }
    
    private func actionCard(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.white)
                .frame(width: 70, height: 70)
                .background(color)
                .cornerRadius(18)
                .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.title3.bold())
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.08), radius: 15, x: 0, y: 8)
    }
}

struct DiagnosticsView: View {
    var body: some View {
        List {
            Section(header: Text("Perception")) {
                NavigationLink(destination: DepthCaptureView()) {
                    Label("LiDAR Capture", systemImage: "cube.transparent")
                        .font(.headline)
                        .padding(.vertical, 4)
                }
            }
            
            Section(header: Text("Estimation")) {
                NavigationLink(destination: ARKitPoseView()) {
                    Label("ARKit 6D Pose", systemImage: "move.3d")
                        .font(.headline)
                        .padding(.vertical, 4)
                }
            }
            
            Section(header: Text("CONTROL")) {
                NavigationLink(destination: MCPTestView()) {
                    Label("Raspberry Pi WiFi", systemImage: "cpu")
                        .font(.headline)
                        .padding(.vertical, 4)
                }
            }
            
            Section(header: Text("Control")) {
                NavigationLink(destination: STM32ControlView()) {
                    Label("STM32 Direct BLE", systemImage: "bolt.horizontal.fill")
                        .font(.headline)
                        .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Diagnostics")
    }
}
