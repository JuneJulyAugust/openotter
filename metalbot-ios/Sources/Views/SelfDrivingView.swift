import SwiftUI
import AudioToolbox

// MARK: - Alarm constants

private enum AlarmConfig {
    static let soundID = SystemSoundID(1005)
    static let repeatIntervalS: TimeInterval = 1.5
}

// MARK: - SelfDrivingView

struct SelfDrivingView: View {
    @StateObject private var viewModel = SelfDrivingViewModel()
    @Environment(\.presentationMode) var presentationMode

    // View state for map interaction
    @State private var scale: CGFloat = 40.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 40.0
    @State private var lastOffset: CGSize = .zero

    // Repeating alarm timer — active while safety override is engaged.
    @State private var alarmTimer: Timer?
    
    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height > geo.size.width
            let screenWidth = geo.size.width
            let screenHeight = geo.size.height
            
            // Invert dimensions if portrait to force landscape layout
            let width = isPortrait ? screenHeight : screenWidth
            let height = isPortrait ? screenWidth : screenHeight
            
            // Fixed safe areas for landscape orientation
            let leftPad: CGFloat = 50.0 // Notch area
            let rightPad: CGFloat = 34.0 // Home indicator area
            let topPad: CGFloat = 20.0
            let bottomPad: CGFloat = 20.0
            
            landscapeContent(leftPad: leftPad, rightPad: rightPad, topPad: topPad, bottomPad: bottomPad)
                .frame(width: width, height: height)
                .rotationEffect(isPortrait ? .degrees(90) : .degrees(0))
                .position(x: screenWidth / 2, y: screenHeight / 2)
        }
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
        .sheet(isPresented: $viewModel.showMapManager) {
            MapManagerView(viewModel: viewModel.poseModel)
        }
    }
    
    @ViewBuilder
    private func landscapeContent(leftPad: CGFloat, rightPad: CGFloat, topPad: CGFloat, bottomPad: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // BACKGROUND: Map Canvas
            mapCanvas
                .zIndex(0)

            // OVERLAYS
            VStack(alignment: .leading, spacing: 0) {
                // TOP BAR
                topBar(leftPad: leftPad, rightPad: rightPad, topPad: topPad)
                    .zIndex(2)

                Spacer()

                // BOTTOM HUD
                bottomHUD(leftPad: leftPad, rightPad: rightPad, bottomPad: bottomPad)
                    .zIndex(1)
            }

            // EMERGENCY BRAKE OVERLAY
            if viewModel.orchestrator.isOverridden {
                emergencyBrakeOverlay
                    .zIndex(10)
            }
        }
        .background(Color(.systemGray6))
        .onChange(of: viewModel.orchestrator.isOverridden) { overridden in
            overridden ? startAlarm() : stopAlarm()
        }
    }
    
    // MARK: - Components
    
    private func topBar(leftPad: CGFloat, rightPad: CGFloat, topPad: CGFloat) -> some View {
        HStack(spacing: 16) {
            // Custom Back Button
            Button(action: {
                viewModel.stop()
                presentationMode.wrappedValue.dismiss()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.body.bold())
                    Text("Home")
                        .font(.subheadline.bold())
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
            
            Spacer()
            
            // Subsystem Status
            HStack(spacing: 16) {
                // ARKit Status + Hz
                HStack(spacing: 6) {
                    Circle()
                        .fill(arkitColor)
                        .frame(width: 8, height: 8)
                    Text("ARKit")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    Text(String(format: "%.0f Hz", viewModel.poseModel.poseHz))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundColor(.cyan)
                    Text(viewModel.poseModel.trackingReason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let pose = viewModel.poseModel.currentPose {
                        Text(String(format: "C:%.0f%%", pose.confidence * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider().frame(height: 16)
                
                // ESC Status
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.escManager.status == .connected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("ESC")
                        .font(.caption.bold())
                }
                
                Divider().frame(height: 16)
                
                // STM32 Status
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.stm32Manager.status == .connected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("STM32")
                        .font(.caption.bold())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            
            Spacer()
            
            // Map Manager Button
            Button(action: {
                viewModel.showMapManager = true
            }) {
                Image(systemName: viewModel.poseModel.activeMapName != nil ? "map.fill" : "map")
                    .font(.body.bold())
                    .foregroundColor(viewModel.poseModel.activeMapName != nil ? .green : .primary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.leading, leftPad)
        .padding(.trailing, rightPad)
        .padding(.top, topPad)
    }
    
    private var arkitColor: Color {
        if viewModel.poseModel.isInterrupted { return .red }
        if viewModel.poseModel.isRelocalizing { return .orange }
        switch viewModel.poseModel.trackingState {
        case .normal: return .green
        case .limited: return .orange
        case .notAvailable: return .red
        @unknown default: return .gray
        }
    }
    
    private func bottomHUD(leftPad: CGFloat, rightPad: CGFloat, bottomPad: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            // LEFT: Telemetry
            VStack(alignment: .leading, spacing: 6) {
                Text("TELEMETRY")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                MetricRow(label: "Motor", value: String(format: "%.2f m/s", viewModel.escManager.telemetry?.speedMps ?? 0.0))
                MetricRow(label: "ARKit", value: String(format: "%.2f m/s", viewModel.poseModel.arkitSpeedMps))
                MetricRow(label: "RPM", value: "\(viewModel.escManager.telemetry?.rpm ?? 0)")
                MetricRow(label: "Voltage", value: String(format: "%.1f V", viewModel.escManager.telemetry?.voltage ?? 0.0))
                MetricRow(label: "Temp", value: String(format: "%.0f C", viewModel.escManager.telemetry?.escTemperature ?? 0.0))
            }
            .padding(12)
            .frame(width: 150)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            
            // LEFT-CENTER: Actuation
            VStack(alignment: .leading, spacing: 6) {
                Text("ACTUATION")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                MetricRow(label: "Steering", value: String(format: "%.0f%%", viewModel.steering * 100))
                MetricRow(label: "Throttle", value: String(format: "%.0f%%", viewModel.throttle * 100))
                MetricRow(label: "Cmds", value: "\(viewModel.stm32Manager.commandsSent)")
            }
            .padding(12)
            .frame(width: 140)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            // SAFETY
            VStack(alignment: .leading, spacing: 6) {
                Text("SAFETY")
                    .font(.caption2.bold())
                    .foregroundColor(viewModel.orchestrator.isOverridden ? .red : .secondary)
                MetricRow(
                    label: "Depth",
                    value: viewModel.poseModel.forwardDepth.map { String(format: "%.2f m", $0) } ?? "—"
                )
                MetricRow(
                    label: "TTC",
                    value: viewModel.orchestrator.lastSupervisorEvent.map { String(format: "%.2f s", $0.ttc) } ?? "—"
                )
                MetricRow(
                    label: "Status",
                    value: viewModel.orchestrator.isOverridden ? "BRAKE" : "OK"
                )
            }
            .padding(12)
            .frame(width: 140)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .fill(viewModel.orchestrator.isOverridden ? Color.red.opacity(0.15) : Color.clear)
            )

            // SPEED TARGET
            VStack(alignment: .leading, spacing: 6) {
                Text("TARGET SPEED")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Text(String(format: "%.2f m/s", viewModel.targetSpeedMps))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundColor(.cyan)
                Slider(
                    value: $viewModel.targetSpeedMps,
                    in: SelfDrivingViewModel.minSpeedMps...SelfDrivingViewModel.maxSpeedMps,
                    step: 0.05
                )
                .tint(.cyan)
                HStack {
                    Text(String(format: "%.1f", SelfDrivingViewModel.minSpeedMps))
                        .font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text("0")
                        .font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", SelfDrivingViewModel.maxSpeedMps))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(12)
            .frame(width: 150)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Spacer()
            
            // RIGHT: ARM / DISARM Control
            Button(action: { viewModel.toggleAutonomous() }) {
                VStack(spacing: 8) {
                    Image(systemName: viewModel.isAutonomous ? "stop.fill" : "play.fill")
                        .font(.system(size: 32, weight: .bold))
                    Text(viewModel.isAutonomous ? "DISARM" : "ARM AUTO")
                        .font(.headline.bold())
                }
                .foregroundColor(.white)
                .frame(width: 120, height: 100)
                .background(viewModel.isAutonomous ? Color.red : Color.blue)
                .cornerRadius(16)
                .shadow(radius: 5)
            }
            .disabled(!viewModel.isStarted)
        }
        .padding(.leading, leftPad)
        .padding(.trailing, rightPad)
        .padding(.bottom, bottomPad)
    }
    
    // MARK: - Alarm

    private func startAlarm() {
        AudioServicesPlayAlertSound(AlarmConfig.soundID)
        alarmTimer = Timer.scheduledTimer(withTimeInterval: AlarmConfig.repeatIntervalS, repeats: true) { _ in
            AudioServicesPlayAlertSound(AlarmConfig.soundID)
        }
    }

    private func stopAlarm() {
        alarmTimer?.invalidate()
        alarmTimer = nil
    }

    // MARK: - Emergency Brake Overlay

    private var emergencyBrakeOverlay: some View {
        VStack(spacing: 8) {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 36))
                    Text("EMERGENCY BRAKE")
                        .font(.title2.bold())
                    if let event = viewModel.orchestrator.lastSupervisorEvent {
                        Text(String(format: "TTC: %.2fs  |  Depth: %.2fm", event.ttc, event.forwardDepth))
                            .font(.caption.monospacedDigit())
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                Spacer()
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var mapCanvas: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                PoseMapView(
                    poses: viewModel.poseModel.poses,
                    currentPose: viewModel.poseModel.currentPose,
                    isTracking: viewModel.poseModel.isTracking,
                    waypoints: viewModel.waypoints,
                    scale: $scale,
                    offset: $offset
                )
                .background(Color(.systemGray6))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(10, min(lastScale * value, 2000))
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                
                // Overlay for scale indicator
                Text("Grid: 1.0 m")
                    .font(.caption.monospaced())
                    .padding(6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .padding(16)
            }
        }
    }
}

