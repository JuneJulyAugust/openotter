import SwiftUI
import simd

struct ARKitPoseView: View {
    @StateObject private var viewModel = ARKitPoseViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    // View state for interaction
    @State private var scale: CGFloat = 40.0 // pixels per meter (~5m visible per side)
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 40.0
    @State private var lastOffset: CGSize = .zero
    @State private var canvasSize: CGSize = .zero
    
    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height > geo.size.width
            let screenWidth = geo.size.width
            let screenHeight = geo.size.height
            
            // Invert dimensions if portrait to force landscape layout
            let width = isPortrait ? screenHeight : screenWidth
            let height = isPortrait ? screenWidth : screenHeight
            
            // Fixed safe areas for iPhone 13 Pro Max (Landscape Left orientation)
            // When physically in portrait but forced landscape:
            // Top of phone (notch) becomes Left padding
            // Bottom of phone (home bar) becomes Right padding
            // We use fixed generous paddings to ensure UI is never clipped.
            let leftPad: CGFloat = 50.0 // Notch area
            let rightPad: CGFloat = 34.0 // Home indicator area
            let topPad: CGFloat = 10.0
            
            landscapeContent(leftPad: leftPad, rightPad: rightPad, topPad: topPad)
                .frame(width: width, height: height)
                .rotationEffect(isPortrait ? .degrees(90) : .degrees(0))
                .position(x: screenWidth / 2, y: screenHeight / 2)
        }
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .onAppear { viewModel.migrateLegacyMap() }
        .onDisappear { viewModel.stop() }
        .alert(isPresented: .constant(viewModel.errorMsg != nil)) {
            Alert(
                title: Text("ARKit Error"),
                message: Text(viewModel.errorMsg ?? ""),
                dismissButton: .default(Text("OK")) {
                    viewModel.errorMsg = nil
                }
            )
        }
        .onChange(of: viewModel.poses.count) { _ in
            if viewModel.isTracking {
                updateAutoZoom(size: canvasSize)
            }
        }
        .sheet(isPresented: $viewModel.showMapManager) {
            MapManagerView(viewModel: viewModel)
        }
    }
    
    @ViewBuilder
    private func landscapeContent(leftPad: CGFloat, rightPad: CGFloat, topPad: CGFloat) -> some View {
        HStack(spacing: 0) {
            // LEFT: Data Panel
            dataPanel(topPad: topPad)
                .padding(.leading, leftPad)
                .frame(width: 160 + leftPad) // Narrower panel
                .background(Color(.systemBackground).shadow(radius: 2))
                .zIndex(1)
            
            // CENTER: Map Canvas
            mapCanvas
                .zIndex(0)
                .clipped()
            
            // RIGHT: Thumb Controls
            controlsPanel
                .padding(.trailing, rightPad)
                .frame(width: 76 + rightPad)
                .background(Color(.systemBackground).shadow(radius: 2))
                .zIndex(1)
        }
        .background(Color(.systemGray6))
    }
    
    private func dataPanel(topPad: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) { // Tighter spacing
            // Custom Back Button
            Button(action: {
                viewModel.stop()
                presentationMode.wrappedValue.dismiss()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.body.bold())
                    Text("Diagnostics")
                        .font(.subheadline)
                }
                .foregroundColor(.blue)
            }
            .padding(.top, topPad + 8)
            
            Divider()
            
            if let pose = viewModel.currentPose {
                VStack(alignment: .leading, spacing: 6) { // Tighter spacing
                    Text(String(format: "X(Fwd): %+.2f", pose.x))
                    Text(String(format: "Y(Up) : %+.2f", pose.y))
                    Text(String(format: "Z(Rgt): %+.2f", pose.z))
                }
                .font(.system(.subheadline, design: .monospaced)) // Smaller font
                
                let yawDeg = pose.yaw * 180 / .pi
                Text(String(format: "Yaw: %+.1f°", yawDeg))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.blue)

                Text(String(format: "Speed: %.2f m/s", viewModel.arkitSpeedMps))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.green)

            } else {
                Text("Waiting...")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            // Tracking State + Hz
            HStack(spacing: 4) {
                Circle()
                    .fill(trackingStateColor)
                    .frame(width: 8, height: 8)
                Text(viewModel.trackingReason)
                    .font(.caption.bold())
                    .foregroundColor(trackingStateColor)
            }
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.caption2)
                    .foregroundColor(.cyan)
                Text(String(format: "%.0f Hz", viewModel.poseHz))
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundColor(.cyan)
            }

            // Interruption / Relocalization warning
            if viewModel.isInterrupted {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("INTERRUPTED")
                        .font(.caption.bold())
                }
                .foregroundColor(.red)
            } else if viewModel.isRelocalizing {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Relocalizing...")
                        .font(.caption.bold())
                }
                .foregroundColor(.orange)
            }

            // Confidence + LiDAR row
            HStack(spacing: 4) {
                Image(systemName: viewModel.isUsingSceneDepth ? "sensor.tag.radiowaves.forward.fill" : "sensor.tag.radiowaves.forward")
                Text(viewModel.isUsingSceneDepth ? "LiDAR" : "LiDAR Off")
                    .font(.caption)
                if let pose = viewModel.currentPose {
                    Text(String(format: "C:%.0f%%", pose.confidence * 100))
                        .font(.caption.bold().monospacedDigit())
                }
            }
            .foregroundColor(viewModel.isUsingSceneDepth ? .cyan : .secondary)

            // Active Map Status
            HStack(spacing: 4) {
                Image(systemName: viewModel.activeMapName != nil ? "map.fill" : "map")
                if let name = viewModel.activeMapName {
                    Text(name)
                        .font(.caption.bold())
                        .lineLimit(1)
                } else if let selID = viewModel.selectedMapID,
                          let sel = viewModel.savedMaps.first(where: { $0.id == selID }) {
                    Text("→ \(sel.name)")
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    Text("No map")
                        .font(.caption)
                }
            }
            .foregroundColor(viewModel.activeMapName != nil ? .green : .secondary)

            Spacer()

            Text("Pts: \(viewModel.poses.count)")
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 10)
    }
    
    private var trackingStateColor: Color {
        if viewModel.isInterrupted { return .red }
        if viewModel.isRelocalizing { return .orange }
        switch viewModel.trackingState {
        case .normal: return .green
        case .limited: return .orange
        case .notAvailable: return .red
        @unknown default: return .gray
        }
    }

    private var controlsPanel: some View {
        VStack(spacing: 12) {
            Spacer()

            // Map Manager
            compactButton(icon: "map", color: .blue) {
                viewModel.showMapManager = true
            }

            // Recenter / Fit View
            compactButton(icon: "location.viewfinder", color: .primary) {
                updateAutoZoom(size: canvasSize)
            }

            // Clear Trajectory
            compactButton(icon: "trash", color: .red) {
                viewModel.clear()
                updateAutoZoom(size: canvasSize)
            }

            // Start / Stop (larger)
            Button(action: {
                if viewModel.isTracking {
                    viewModel.stop()
                } else {
                    viewModel.start()
                }
            }) {
                Image(systemName: viewModel.isTracking ? "stop.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(viewModel.isTracking ? Color.red : Color.blue)
                    .clipShape(Circle())
                    .shadow(radius: 3)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
    }

    private func compactButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(Color(.systemGray5))
                .clipShape(Circle())
        }
    }
    
    private var mapCanvas: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                PoseMapView(
                    poses: viewModel.poses,
                    currentPose: viewModel.currentPose,
                    isTracking: viewModel.isTracking,
                    scale: $scale,
                    offset: $offset
                )
                .background(Color(.systemGray6))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !viewModel.isTracking {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if !viewModel.isTracking {
                                scale = max(10, min(lastScale * value, 2000))
                            }
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
            .onAppear {
                canvasSize = geo.size
                updateAutoZoom(size: geo.size)
            }
            .onChange(of: geo.size) { newSize in
                canvasSize = newSize
                if viewModel.isTracking {
                    updateAutoZoom(size: newSize)
                }
            }
        }
    }
    
    // MARK: - Auto Zoom
    
    private func updateAutoZoom(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        
        let allPoses = viewModel.poses + (viewModel.currentPose.map { [$0] } ?? [])
        guard !allPoses.isEmpty else {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.scale = 40.0
                self.offset = .zero
            }
            self.lastScale = 40.0
            self.lastOffset = .zero
            return
        }
        
        var minX = allPoses[0].x
        var maxX = allPoses[0].x
        var minZ = allPoses[0].z
        var maxZ = allPoses[0].z
        
        for p in allPoses {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minZ = min(minZ, p.z)
            maxZ = max(maxZ, p.z)
        }
        
        let rangeX = CGFloat(maxX - minX)
        let rangeZ = CGFloat(maxZ - minZ)
        
        let padding: CGFloat = 80 // Increased Canvas padding to accommodate axes and texts
        let availableWidth = size.width - padding * 2
        let availableHeight = size.height - padding * 2
        
        // Scale to fit ranges. If range is tiny, default to 40 pixels/m (~5m visible).
        let scaleX = rangeZ > 0.05 ? availableWidth / rangeZ : 40.0
        let scaleY = rangeX > 0.05 ? availableHeight / rangeX : 40.0
        
        let targetScale = min(scaleX, scaleY)
        let finalScale = max(20, min(targetScale, 400)) // Clamp scale limits
        
        let centerX = CGFloat(minZ + maxZ) / 2.0
        let centerY = CGFloat(minX + maxX) / 2.0
        
        let targetOffset = CGSize(
            width: -centerX * finalScale,
            height: centerY * finalScale // centerY is positive because Canvas Y is inverted
        )
        
        withAnimation(.easeInOut(duration: 0.1)) {
            self.scale = finalScale
            self.offset = targetOffset
        }
        
        self.lastScale = finalScale
        self.lastOffset = targetOffset
    }
}
