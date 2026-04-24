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
                TofCell(sensor: frame.sensor,
                        reading: frame.zones[i],
                        maxRangeMm: maxRangeMm)
                    .aspectRatio(1.0, contentMode: .fit)
            }
        }
    }
}

private struct TofCell: View {
    let sensor: TofSensorType
    let reading: ZoneReading
    let maxRangeMm: UInt16

    var body: some View {
        ZStack {
            /* Always render the heat color. Previously we greyed out cells
             * with non-OK status, but the VL53L1 routinely flips to
             * SIG/PHA/? between scans and the resulting flash made the
             * grid unreadable. Status is carried by the border style and
             * the small status label below the range number instead. */
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hue: hue, saturation: 0.85, brightness: 0.9))

            VStack(spacing: 2) {
                Text("\(reading.rangeMm)")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 0)
                Text("mm")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                Text(statusLabel)
                    .font(.system(size: 8, design: .monospaced).bold())
                    .padding(.horizontal, 3)
                    .background(Color.black.opacity(0.35))
                    .foregroundColor(statusLabelColor)
                    .cornerRadius(2)
            }
            .padding(4)
            .minimumScaleFactor(0.5)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(style: StrokeStyle(
                    lineWidth: 2,
                    dash: isUsable ? [] : [3]))
                .foregroundColor(borderColor)
        )
    }

    private var isUsable: Bool {
        if sensor == .vl53l5cx {
            return reading.status.rawValue == 5 || reading.status.rawValue == 9
        }
        return reading.status.isUsable
    }

    private var statusLabel: String {
        if sensor == .vl53l5cx {
            return isUsable ? "OK" : "\(reading.status.rawValue)"
        }
        return reading.status.shortLabel
    }

    /// Tint for the small status pill — muted white for OK, accent for others
    /// so the label stands out without repainting the entire cell.
    private var statusLabelColor: Color {
        if sensor == .vl53l5cx {
            return isUsable ? .white : .orange
        }
        switch reading.status {
        case .valid:                              return .white
        case .minRangeClipped, .noWrapCheckFail:  return .yellow
        case .rangeInvalid, .unknown:             return .white.opacity(0.85)
        default:                                  return .orange
        }
    }

    private var hue: Double {
        let cap = max(maxRangeMm, 1)
        let r = min(reading.rangeMm, cap)
        // 0 mm → red (0.0); maxRangeMm → blue (~0.66).
        return Double(r) / Double(cap) * 0.66
    }

    private var borderColor: Color {
        if sensor == .vl53l5cx {
            return isUsable ? .green : .red
        }
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
