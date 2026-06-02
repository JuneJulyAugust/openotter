import Foundation

struct TofHealthPresentation: Equatable {
    let statusText: String
    let detailText: String
    let compactDetailText: String
    let isError: Bool

    init(state: TofState, lastError: UInt8, scanHz: UInt8) {
        statusText = {
            switch state {
            case .idle: return "IDLE"
            case .running: return "RUNNING"
            case .error: return "ERROR"
            case .unknown: return "UNKNOWN"
            }
        }()

        detailText = Self.detail(lastError: lastError, scanHz: scanHz)
        compactDetailText = Self.compactDetail(lastError: lastError, scanHz: scanHz)
        isError = state == .error || [1, 2, 3, 5, 6].contains(lastError)
    }

    private static func detail(lastError: UInt8, scanHz: UInt8) -> String {
        switch lastError {
        case 0: return "\(scanHz) Hz"
        case 1: return "VL53L8CX not detected"
        case 2: return "VL53L8CX boot failed"
        case 3: return "VL53L8CX I2C error"
        case 4: return "Firmware rejected VL53L8CX config"
        case 5: return "VL53L8CX driver missing"
        case 6: return "VL53L8CX driver offline"
        case 11: return "Config locked outside Debug mode"
        default: return "ToF error \(lastError)"
        }
    }

    private static func compactDetail(lastError: UInt8, scanHz: UInt8) -> String {
        switch lastError {
        case 0: return "\(scanHz) Hz"
        case 1: return "No sensor"
        case 2: return "Boot fail"
        case 3: return "I2C"
        case 4: return "Config"
        case 5: return "Missing"
        case 6: return "Offline"
        case 11: return "Locked"
        default: return "Err \(lastError)"
        }
    }
}
