import SwiftUI

/// Heat-mapped grid renderer for one TofFrame. Hue ramps red→blue across the
/// configurable max range; invalid cells render greyed with a dashed border.
struct TofGridView: View {
    let frame: TofFrame
    let maxRangeMm: UInt16

    var body: some View {
        let cols = Array(
            repeating: GridItem(.flexible(), spacing: 4),
            count: max(1, Int(frame.layout)))

        LazyVGrid(columns: cols, spacing: 4) {
            ForEach(frame.zones.indices, id: \.self) { i in
                TofCell(reading: frame.zones[i], maxRangeMm: maxRangeMm)
                    .aspectRatio(1.0, contentMode: .fit)
            }
        }
    }
}

private struct TofCell: View {
    let reading: ZoneReading
    let maxRangeMm: UInt16

    var body: some View {
        ZStack {
            background
            VStack(spacing: 2) {
                Text("\(reading.rangeMm)")
                    .font(.system(.caption, design: .monospaced).bold())
                Text("mm")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(reading.status.shortLabel)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(borderColor)
            }
            .padding(4)
            .minimumScaleFactor(0.5)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(style: StrokeStyle(
                    lineWidth: 2,
                    dash: reading.status.isUsable ? [] : [3]))
                .foregroundColor(borderColor)
        )
    }

    @ViewBuilder
    private var background: some View {
        if reading.status.isUsable {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hue: hue, saturation: 0.85, brightness: 0.9))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.25))
        }
    }

    private var hue: Double {
        let cap = max(maxRangeMm, 1)
        let r = min(reading.rangeMm, cap)
        // 0 mm → red (0.0); maxRangeMm → blue (~0.66).
        return Double(r) / Double(cap) * 0.66
    }

    private var borderColor: Color {
        switch reading.status {
        case .valid:                          return .green
        case .minRangeClipped, .noWrapCheckFail: return .yellow
        case .rangeInvalid:                    return .gray
        default:                               return .red
        }
    }
}

#if DEBUG
private func _tofPreviewFrame() -> TofFrame {
    var zones: [ZoneReading] = []
    for i in 0..<16 {
        let status: VL53L1RangeStatus = (i % 5 == 0) ? .signalFail : .valid
        zones.append(ZoneReading(rangeMm: UInt16(200 + i * 110), status: status))
    }
    return TofFrame(seq: 1,
                    budgetUsPerZone: 8000,
                    layout: 4,
                    distMode: 1,
                    numZones: 16,
                    zones: zones)
}

#Preview("4x4 sample") {
    TofGridView(frame: _tofPreviewFrame(), maxRangeMm: 2000).padding()
}
#endif
