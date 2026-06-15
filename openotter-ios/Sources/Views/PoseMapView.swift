import SwiftUI

// MARK: - Drawing constants

private enum MapStyle {
    static let waypointRadius: CGFloat = 7
    static let waypointLineWidth: CGFloat = 2
    static let trajectoryLineDash: [CGFloat] = [8, 4]
    static let trajectoryLineWidth: CGFloat = 2
    static let referenceLineWidth: CGFloat = 9
    static let referenceArrowLength: CGFloat = 15
    static let referenceArrowHeadLength: CGFloat = 7
    static let referenceArrowCount = 10
}

// MARK: - PoseMapView

/// A reusable 2D canvas for displaying robot trajectory and current pose.
struct PoseMapView: View {
    let poses: [PoseEntry]
    let currentPose: PoseEntry?
    let isTracking: Bool
    var waypoints: [Waypoint] = []
    var referenceWaypoints: [Waypoint] = []

    @Binding var scale: CGFloat
    @Binding var offset: CGSize

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(
                x: size.width / 2 + offset.width,
                y: size.height / 2 + offset.height
            )

            drawGrid(context: context, size: size, center: center)
            drawAxes(context: context, size: size, center: center)
            drawPath(context: context, center: center)
            drawReferenceWaypoints(context: context, center: center)
            drawWaypoints(context: context, center: center)
            drawCurrentPose(context: context, center: center)
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

        // Z Axis (Right)
        var zAxis = Path()
        zAxis.move(to: center)
        let zEnd = CGPoint(x: size.width, y: center.y)
        zAxis.addLine(to: zEnd)

        zAxis.move(to: zEnd)
        zAxis.addLine(to: CGPoint(x: zEnd.x - cos(arrowAngle) * arrowLen, y: zEnd.y - sin(arrowAngle) * arrowLen))
        zAxis.move(to: zEnd)
        zAxis.addLine(to: CGPoint(x: zEnd.x - cos(arrowAngle) * arrowLen, y: zEnd.y + sin(arrowAngle) * arrowLen))

        context.stroke(zAxis, with: .color(axisColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

        // X Axis (Forward = Up on Canvas)
        var xAxis = Path()
        xAxis.move(to: center)
        let xEnd = CGPoint(x: center.x, y: 0)
        xAxis.addLine(to: xEnd)

        xAxis.move(to: xEnd)
        xAxis.addLine(to: CGPoint(x: xEnd.x - sin(arrowAngle) * arrowLen, y: xEnd.y + cos(arrowAngle) * arrowLen))
        xAxis.move(to: xEnd)
        xAxis.addLine(to: CGPoint(x: xEnd.x + sin(arrowAngle) * arrowLen, y: xEnd.y + cos(arrowAngle) * arrowLen))

        context.stroke(xAxis, with: .color(axisColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    private func drawPath(context: GraphicsContext, center: CGPoint) {
        guard !poses.isEmpty else {
            context.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(.orange))
            return
        }

        let count = poses.count

        if isTracking || count < 2 {
            var path = Path()
            for (index, pose) in poses.enumerated() {
                let pt = canvasPoint(x: pose.x, z: pose.z, center: center)
                index == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            context.stroke(path, with: .color(.cyan), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        } else {
            for i in 1..<count {
                let pt1 = canvasPoint(x: poses[i-1].x, z: poses[i-1].z, center: center)
                let pt2 = canvasPoint(x: poses[i].x,   z: poses[i].z,   center: center)
                var segment = Path()
                segment.move(to: pt1)
                segment.addLine(to: pt2)
                let fraction = Double(i) / Double(count - 1)
                context.stroke(segment, with: .color(jetColor(for: fraction)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }

        context.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)), with: .color(.orange))
    }

    private func drawWaypoints(context: GraphicsContext, center: CGPoint) {
        guard !waypoints.isEmpty else { return }

        if waypoints.count > 8 {
            drawWaypointStartMarker(waypoints: waypoints, context: context, center: center)
            return
        }

        if let pose = currentPose {
            drawTrajectoryLine(
                from: canvasPoint(x: pose.x, z: pose.z, center: center),
                to: canvasPoint(x: waypoints[0].x, z: waypoints[0].z, center: center),
                context: context
            )
        }

        for wp in waypoints {
            drawWaypointMarker(at: canvasPoint(x: wp.x, z: wp.z, center: center), context: context)
        }
    }

    private func drawReferenceWaypoints(context: GraphicsContext, center: CGPoint) {
        guard referenceWaypoints.count > 1 else { return }

        var path = Path()
        for (index, waypoint) in referenceWaypoints.enumerated() {
            let pt = canvasPoint(x: waypoint.x, z: waypoint.z, center: center)
            index == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        if let first = referenceWaypoints.first {
            path.addLine(to: canvasPoint(x: first.x, z: first.z, center: center))
        }

        context.stroke(
            path,
            with: .color(.red.opacity(0.30)),
            style: StrokeStyle(
                lineWidth: MapStyle.referenceLineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )

        drawReferenceArrows(waypoints: referenceWaypoints, context: context, center: center)
        drawWaypointStartMarker(waypoints: referenceWaypoints, context: context, center: center)
    }

    private func drawReferenceArrows(waypoints: [Waypoint], context: GraphicsContext, center: CGPoint) {
        guard waypoints.count > 2 else { return }

        let arrowCount = min(MapStyle.referenceArrowCount, max(1, waypoints.count / 18))
        let arrowStride = max(1, waypoints.count / arrowCount)
        for index in stride(from: arrowStride / 2, to: waypoints.count, by: arrowStride) {
            let start = waypoints[index]
            let end = waypoints[(index + 2) % waypoints.count]
            drawDirectionArrow(
                from: canvasPoint(x: start.x, z: start.z, center: center),
                to: canvasPoint(x: end.x, z: end.z, center: center),
                context: context
            )
        }
    }

    private func drawDirectionArrow(from start: CGPoint, to end: CGPoint, context: GraphicsContext) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(0.001, sqrt(dx * dx + dy * dy))
        let ux = dx / length
        let uy = dy / length
        let arrowLength = MapStyle.referenceArrowLength
        let tip = CGPoint(x: start.x + ux * arrowLength, y: start.y + uy * arrowLength)
        let base = CGPoint(x: tip.x - ux * MapStyle.referenceArrowHeadLength,
                           y: tip.y - uy * MapStyle.referenceArrowHeadLength)
        let normal = CGPoint(x: -uy, y: ux)
        let wing: CGFloat = 4

        var arrow = Path()
        arrow.move(to: start)
        arrow.addLine(to: tip)
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: base.x + normal.x * wing, y: base.y + normal.y * wing))
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: base.x - normal.x * wing, y: base.y - normal.y * wing))

        context.stroke(
            arrow,
            with: .color(.red.opacity(0.55)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawWaypointStartMarker(waypoints: [Waypoint], context: GraphicsContext, center: CGPoint) {
        guard waypoints.count > 1, let first = waypoints.first else { return }

        let start = canvasPoint(x: first.x, z: first.z, center: center)
        let next = canvasPoint(x: waypoints[1].x, z: waypoints[1].z, center: center)
        let r = MapStyle.waypointRadius

        context.fill(
            Path(ellipseIn: CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2)),
            with: .color(.orange)
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2)),
            with: .color(.white.opacity(0.9)),
            lineWidth: 2
        )
        drawDirectionArrow(from: start, to: next, context: context)
    }

    private func drawTrajectoryLine(from: CGPoint, to: CGPoint, context: GraphicsContext) {
        var line = Path()
        line.move(to: from)
        line.addLine(to: to)
        context.stroke(
            line,
            with: .color(.red.opacity(0.5)),
            style: StrokeStyle(lineWidth: MapStyle.trajectoryLineWidth, dash: MapStyle.trajectoryLineDash)
        )
    }

    private func drawWaypointMarker(at pt: CGPoint, context: GraphicsContext) {
        let r = MapStyle.waypointRadius
        context.stroke(
            Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
            with: .color(.red),
            lineWidth: MapStyle.waypointLineWidth
        )
        var cross = Path()
        cross.move(to: CGPoint(x: pt.x - r, y: pt.y)); cross.addLine(to: CGPoint(x: pt.x + r, y: pt.y))
        cross.move(to: CGPoint(x: pt.x, y: pt.y - r)); cross.addLine(to: CGPoint(x: pt.x, y: pt.y + r))
        context.stroke(cross, with: .color(.red), lineWidth: MapStyle.waypointLineWidth)
    }

    private func drawCurrentPose(context: GraphicsContext, center: CGPoint) {
        guard let pose = currentPose else { return }
        let pt = canvasPoint(x: pose.x, z: pose.z, center: center)

        context.fill(Path(ellipseIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)), with: .color(.green))

        let canvasAngle = -CGFloat.pi / 2 - CGFloat(pose.yaw)
        let arrowLen: CGFloat = 24
        let endPt = CGPoint(
            x: pt.x + cos(canvasAngle) * arrowLen,
            y: pt.y + sin(canvasAngle) * arrowLen
        )

        var arrowPath = Path()
        arrowPath.move(to: pt)
        arrowPath.addLine(to: endPt)

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

    /// Convert robot-frame (x, z) to canvas coordinates.
    /// Robot +X maps to canvas up (-Y); robot +Z maps to canvas right (+X).
    private func canvasPoint(x: Float, z: Float, center: CGPoint) -> CGPoint {
        CGPoint(
            x: center.x + CGFloat(z) * scale,
            y: center.y - CGFloat(x) * scale
        )
    }

    private func jetColor(for t: Double) -> Color {
        let r = max(0, min(1, 1.5 - abs(4 * t - 3)))
        let g = max(0, min(1, 1.5 - abs(4 * t - 2)))
        let b = max(0, min(1, 1.5 - abs(4 * t - 1)))
        return Color(red: r, green: g, blue: b)
    }
}
