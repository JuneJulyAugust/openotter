import Foundation

/// VL53L1 range-status codes — subset we surface in the UI.
/// Wire authority: firmware Drivers/VL53L1CB/core/inc/vl53l1_def.h.
public enum VL53L1RangeStatus: UInt8, Equatable, Sendable {
    case valid             = 0
    case sigmaFail         = 1
    case signalFail        = 2
    case minRangeClipped   = 3
    case outOfBounds       = 4
    case hardwareFail      = 5
    case noWrapCheckFail   = 6
    case wrapTargetFail    = 7
    case rangeInvalid      = 14
    case unknown           = 255

    public init(raw: UInt8) {
        self = VL53L1RangeStatus(rawValue: raw) ?? .unknown
    }

    /// Three-letter UI tag.
    public var shortLabel: String {
        switch self {
        case .valid:           return "OK"
        case .sigmaFail:       return "SGM"
        case .signalFail:      return "SIG"
        case .minRangeClipped: return "MIN"
        case .outOfBounds:     return "OOB"
        case .hardwareFail:    return "HW"
        case .noWrapCheckFail: return "NWC"
        case .wrapTargetFail:  return "WRP"
        case .rangeInvalid:    return "—"
        case .unknown:         return "?"
        }
    }

    /// Treat as a usable distance reading.
    public var isUsable: Bool {
        self == .valid || self == .minRangeClipped || self == .noWrapCheckFail
    }
}

public struct ZoneReading: Equatable, Sendable {
    public let rangeMm: UInt16
    public let status: VL53L1RangeStatus
}

public struct TofConfig: Equatable, Sendable {
    /// Zones per side: 1, 3, or 4.
    public var layout: UInt8
    /// 1 = SHORT, 2 = MEDIUM, 3 = LONG.
    public var distMode: UInt8
    /// Per-zone timing budget, microseconds.
    public var budgetUs: UInt32

    public init(layout: UInt8, distMode: UInt8, budgetUs: UInt32) {
        self.layout = layout
        self.distMode = distMode
        self.budgetUs = budgetUs
    }

    /// Minimum per-zone budget (µs) that the firmware will accept for a given
    /// (layout, distMode) combo. Must mirror firmware `TofL1_MinBudgetUs` —
    /// if the firmware matrix changes, this must change too.
    public static func minBudgetUs(layout: UInt8, distMode: UInt8) -> UInt32 {
        if layout == 1 {
            switch distMode {
            case 1:  return 20_000   // SHORT
            case 2:  return 33_000   // MEDIUM
            case 3:  return 33_000   // LONG
            default: return 33_000
            }
        } else {
            switch distMode {
            case 1:  return  8_000
            case 2:  return 14_000
            case 3:  return 16_000
            default: return 16_000
            }
        }
    }

    /// Maximum per-zone budget: keep the total scan (budget × zones) under 1 s.
    public static func maxBudgetUs(layout: UInt8) -> UInt32 {
        let zones = UInt32(max(1, layout)) * UInt32(max(1, layout))
        return 1_000_000 / zones
    }

    /// Clamp a requested budget into the (min, max) window for this combo.
    public static func clampBudget(_ requestedUs: UInt32,
                                   layout: UInt8,
                                   distMode: UInt8) -> UInt32 {
        let lo = minBudgetUs(layout: layout, distMode: distMode)
        let hi = max(lo, maxBudgetUs(layout: layout))
        return max(lo, min(hi, requestedUs))
    }
}

public enum TofState: UInt8, Equatable, Sendable {
    case idle    = 0
    case running = 1
    case error   = 2
    case unknown = 255

    public init(raw: UInt8) {
        self = TofState(rawValue: raw) ?? .unknown
    }
}

/// Decoded view of the 76-byte FE62 notification.
public struct TofFrame: Equatable, Sendable {
    public let seq: UInt32
    public let budgetUsPerZone: UInt16
    public let layout: UInt8
    public let distMode: UInt8
    public let numZones: UInt8
    public let zones: [ZoneReading]
}
