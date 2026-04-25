import Foundation

public enum TofSensorType: UInt8, Equatable, Sendable {
    case none = 0
    case vl53l1cb = 1
    case vl53l5cx = 2
    case unknown = 255

    public init(raw: UInt8) {
        self = TofSensorType(rawValue: raw) ?? .unknown
    }
}

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
    public let flags: UInt8

    public init(rangeMm: UInt16, status: VL53L1RangeStatus, flags: UInt8 = 0) {
        self.rangeMm = rangeMm
        self.status = status
        self.flags = flags
    }
}

public struct TofConfig: Equatable, Sendable {
    public var sensor: TofSensorType
    /// Zones per side: 1, 3, or 4.
    public var layout: UInt8
    /// L1: 1 = SHORT, 2 = MEDIUM, 3 = LONG. L5: profile id.
    public var distMode: UInt8
    /// Per-zone timing budget, microseconds.
    public var budgetUs: UInt32
    /// L5 ranging frequency in Hz; 0 lets firmware choose default.
    public var frequencyHz: UInt8
    /// L5 integration time in ms; 0 lets firmware choose default.
    public var integrationMs: UInt16

    public init(sensor: TofSensorType = .vl53l1cb,
                layout: UInt8,
                distMode: UInt8,
                budgetUs: UInt32,
                frequencyHz: UInt8 = 0,
                integrationMs: UInt16 = 0) {
        self.sensor = sensor
        self.layout = layout
        self.distMode = distMode
        self.budgetUs = budgetUs
        self.frequencyHz = frequencyHz
        self.integrationMs = integrationMs
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

    public static func maxL5FrequencyHz(layout: UInt8) -> UInt8 {
        layout == 8 ? 15 : 60
    }

    /// Maximum frequency that keeps 8x8 BLE chunk throughput manageable.
    /// 8x8 frames require 16 chunks each. At 10 Hz that is 160 notifications/sec,
    /// which overflows the BlueNRG-MS TX buffer.
    /// At 1 Hz it is 16 notifications/sec — comfortably within budget.
    /// 4x4 frames need only 5 chunks; 10 Hz = 50 notifications/sec, no cap needed.
    public static func bleCapFrequencyHz(layout: UInt8) -> UInt8 {
        layout == 8 ? 1 : 10
    }

    public static func maxL5IntegrationMs(frequencyHz: UInt8) -> UInt16 {
        let hz = max(1, UInt16(frequencyHz))
        return max(2, 1000 / hz)
    }

    public static func clampL5IntegrationMs(_ requestedMs: UInt16,
                                            frequencyHz: UInt8) -> UInt16 {
        let hi = maxL5IntegrationMs(frequencyHz: frequencyHz)
        return min(max(requestedMs, 2), hi)
    }

    /// Sensible integration-time default per layout. 8x8 spreads the photon
    /// budget over 64 zones; at 20ms most zones return no-target. 100ms gives
    /// each zone adequate signal while fitting within a 1 Hz period (1000ms).
    public static func defaultL5IntegrationMs(layout: UInt8) -> UInt16 {
        layout == 8 ? 100 : 20
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
    public let sensor: TofSensorType
    public let seq: UInt32
    public let budgetUsPerZone: UInt16
    public let layout: UInt8
    public let distMode: UInt8
    public let numZones: UInt8
    public let zones: [ZoneReading]

    public init(sensor: TofSensorType = .vl53l1cb,
                seq: UInt32,
                budgetUsPerZone: UInt16,
                layout: UInt8,
                distMode: UInt8,
                numZones: UInt8,
                zones: [ZoneReading]) {
        self.sensor = sensor
        self.seq = seq
        self.budgetUsPerZone = budgetUsPerZone
        self.layout = layout
        self.distMode = distMode
        self.numZones = numZones
        self.zones = zones
    }
}
