import SwiftUI
import simd

struct ARKitPoseView: View {
    @StateObject private var viewModel = ARKitPoseViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    // View state for interaction
    @State private var scale: CGFloat = 100.0 // pixels per meter
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 100.0
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
        .ignoresSafeArea() // Take over the entire physical screen
        .navigationBarHidden(true) // Hide the system nav bar so it doesn't look weird when rotated
        .onDisappear {
            viewModel.stop()
        }
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
                .frame(width: 100 + rightPad)
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
                        .font(.body.bold()) // Smaller
                    Text("Back")
                        .font(.subheadline) // Smaller
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
                
            } else {
                Text("Waiting...")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            // Tracking State Display
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.trackingState == .normal ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.trackingReason)
                    .font(.caption.bold())
                    .foregroundColor(viewModel.trackingState == .normal ? .green : .orange)
            }
            
            // LiDAR Status Display
            HStack(spacing: 4) {
                Image(systemName: viewModel.isUsingSceneDepth ? "sensor.tag.radiowaves.forward.fill" : "sensor.tag.radiowaves.forward")
                Text(viewModel.isUsingSceneDepth ? "LiDAR Active" : "LiDAR Off")
                    .font(.caption)
            }
            .foregroundColor(viewModel.isUsingSceneDepth ? .cyan : .secondary)
            
            Spacer()
            
            Text("Pts: \(viewModel.poses.count)")
                .font(.caption.monospaced()) // Smaller font
                .foregroundColor(.secondary)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 10) // Tighter internal padding
    }
    
    private var controlsPanel: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Recenter / Fit View
            Button(action: {
                updateAutoZoom(size: canvasSize)
            }) {
                Image(systemName: "location.viewfinder")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 60, height: 60)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            
            // Clear Data
            Button(action: {
                viewModel.clear()
                updateAutoZoom(size: canvasSize)
            }) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.red)
                    .frame(width: 60, height: 60)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            
            // Start / Stop
            Button(action: {
                if viewModel.isTracking {
                    viewModel.stop()
                } else {
                    viewModel.start()
                }
            }) {
                Image(systemName: viewModel.isTracking ? "stop.fill" : "play.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 72, height: 72)
                    .background(viewModel.isTracking ? Color.red : Color.blue)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
    }
    
    private var mapCanvas: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Canvas { context, size in
                    let center = CGPoint(
                        x: size.width / 2 + offset.width,
                        y: size.height / 2 + offset.height
                    )
                    
                    drawGrid(context: context, size: size, center: center)
                    drawAxes(context: context, size: size, center: center)
                    drawPath(context: context, center: center)
                    drawCurrentPose(context: context, center: center)
                }
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
    
    // MARK: - Core Drawing Logic
    
    private func drawGrid(context: GraphicsContext, size: CGSize, center: CGPoint) {
        var path = Path()
        let step = scale // 1 meter grid interval
        
        let startX = Int(-center.x / step) - 1
        let endX = Int((size.width - center.x) / step) + 1
        let startY = Int(-center.y / step) - 1
        let endY = Int((size.height - center.y) / step) + 1
        
        for x in startX...endX {
            let px = center.x + CGFloat(x) * step
            path.move(to: CGPoint(x: px, y: 0))
            path.addLine(to: CGPoint(x: px, y: size.height))
        }
        
        for y in startY...endY {
            let py = center.y + CGFloat(y) * step
            path.move(to: CGPoint(x: 0, y: py))
            path.addLine(to: CGPoint(x: size.width, y: py))
        }
        
        context.stroke(path, with: .color(.gray.opacity(0.3)), lineWidth: 1)
    }
    
    private func drawAxes(context: GraphicsContext, size: CGSize, center: CGPoint) {
        let axisColor = Color.black
        let lineWidth: CGFloat = 2.0
        let arrowLen: CGFloat = 12.0
        let arrowAngle: CGFloat = .pi / 6
        
        // Z Axis (Right) - Extends to the right edge of the screen
        var zAxis = Path()
        zAxis.move(to: center)
        let zEnd = CGPoint(x: size.width, y: center.y)
        zAxis.addLine(to: zEnd)
        
        // Z Arrow head
        zAxis.move(to: zEnd)
        zAxis.addLine(to: CGPoint(x: zEnd.x - cos(arrowAngle) * arrowLen, y: zEnd.y - sin(arrowAngle) * arrowLen))
        zAxis.move(to: zEnd)
        zAxis.addLine(to: CGPoint(x: zEnd.x - cos(arrowAngle) * arrowLen, y: zEnd.y + sin(arrowAngle) * arrowLen))
        
        context.stroke(zAxis, with: .color(axisColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        context.draw(Text("Z"), at: CGPoint(x: size.width - 20, y: center.y - 20))
        
        // X Axis (Forward = Up on Canvas) - Extends to the top edge of the screen
        var xAxis = Path()
        xAxis.move(to: center)
        let xEnd = CGPoint(x: center.x, y: 0)
        xAxis.addLine(to: xEnd)
        
        // X Arrow head (pointing Up on canvas, which is -Y)
        xAxis.move(to: xEnd)
        xAxis.addLine(to: CGPoint(x: xEnd.x - sin(arrowAngle) * arrowLen, y: xEnd.y + cos(arrowAngle) * arrowLen))
        xAxis.move(to: xEnd)
        xAxis.addLine(to: CGPoint(x: xEnd.x + sin(arrowAngle) * arrowLen, y: xEnd.y + cos(arrowAngle) * arrowLen))
        
        context.stroke(xAxis, with: .color(axisColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        context.draw(Text("X"), at: CGPoint(x: center.x + 20, y: 20))
    }
    
    private func jetColor(for t: Double) -> Color {
        // Jet colormap approximation: t in [0, 1] goes Blue -> Cyan -> Green -> Yellow -> Red
        let r = max(0, min(1, 1.5 - abs(4 * t - 3)))
        let g = max(0, min(1, 1.5 - abs(4 * t - 2)))
        let b = max(0, min(1, 1.5 - abs(4 * t - 1)))
        return Color(red: r, green: g, blue: b)
    }

    private func drawPath(context: GraphicsContext, center: CGPoint) {
        let poses = viewModel.poses
        guard !poses.isEmpty else {
            // Draw Origin even if empty
            context.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(.orange))
            return
        }
        
        let count = poses.count
        
        if viewModel.isTracking || count < 2 {
            // Draw single color line while tracking
            var path = Path()
            for (index, pose) in poses.enumerated() {
                // Map Robot(X, Z) to Canvas(Y, X) -> Forward(+X) moves Up(-Y on canvas)
                let canvasX = center.x + CGFloat(pose.z) * scale
                let canvasY = center.y - CGFloat(pose.x) * scale
                let pt = CGPoint(x: canvasX, y: canvasY)
                
                if index == 0 {
                    path.move(to: pt)
                } else {
                    path.addLine(to: pt)
                }
            }
            context.stroke(path, with: .color(.cyan), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        } else {
            // Draw time-based colormap (Jet) when stopped
            for i in 1..<count {
                let p1 = poses[i-1]
                let p2 = poses[i]
                
                let pt1 = CGPoint(x: center.x + CGFloat(p1.z) * scale, y: center.y - CGFloat(p1.x) * scale)
                let pt2 = CGPoint(x: center.x + CGFloat(p2.z) * scale, y: center.y - CGFloat(p2.x) * scale)
                
                var segment = Path()
                segment.move(to: pt1)
                segment.addLine(to: pt2)
                
                let fraction = Double(i) / Double(count - 1)
                context.stroke(segment, with: .color(jetColor(for: fraction)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        
        // Draw Origin Indicator (Orange)
        context.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(.orange))
    }
    
    private func drawCurrentPose(context: GraphicsContext, center: CGPoint) {
        guard let pose = viewModel.currentPose else { return }
        
        let canvasX = center.x + CGFloat(pose.z) * scale
        let canvasY = center.y - CGFloat(pose.x) * scale
        let pt = CGPoint(x: canvasX, y: canvasY)
        
        // Draw green dot for current position
        context.fill(Path(ellipseIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)), with: .color(.green))
        
        // Yaw = 0 is Forward (Canvas -Y). Positive Yaw is Left (Canvas -X).
        let canvasAngle = -CGFloat.pi / 2 - CGFloat(pose.yaw)
        
        let arrowLen: CGFloat = 24
        let endPt = CGPoint(
            x: pt.x + cos(canvasAngle) * arrowLen,
            y: pt.y + sin(canvasAngle) * arrowLen
        )
        
        var arrowPath = Path()
        arrowPath.move(to: pt)
        arrowPath.addLine(to: endPt)
        
        // Arrow head
        let headAngle: CGFloat = .pi / 6
        let headLen: CGFloat = 10
        let p1 = CGPoint(
            x: endPt.x - cos(canvasAngle - headAngle) * headLen,
            y: endPt.y - sin(canvasAngle - headAngle) * headLen
        )
        let p2 = CGPoint(
            x: endPt.x - cos(canvasAngle + headAngle) * headLen,
            y: endPt.y - sin(canvasAngle + headAngle) * headLen
        )
        
        arrowPath.move(to: endPt)
        arrowPath.addLine(to: p1)
        arrowPath.move(to: endPt)
        arrowPath.addLine(to: p2)
        
        context.stroke(arrowPath, with: .color(.green), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }
    
    private func updateAutoZoom(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        
        let allPoses = viewModel.poses + (viewModel.currentPose.map { [$0] } ?? [])
        guard !allPoses.isEmpty else {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.scale = 100.0
                self.offset = .zero
            }
            self.lastScale = 100.0
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
        
        // Scale to fit ranges. If range is tiny, default to 150 pixels/m.
        let scaleX = rangeZ > 0.05 ? availableWidth / rangeZ : 150.0
        let scaleY = rangeX > 0.05 ? availableHeight / rangeX : 150.0
        
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
