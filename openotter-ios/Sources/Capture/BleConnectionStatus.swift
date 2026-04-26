import Foundation

/// Shared BLE connection state for both the STM32 and ESC managers.
///
/// `STM32BleStatus` and `ESCBleStatus` previously held identical case
/// lists; routing both through this enum eliminates the duplicate type
/// and lets shared code (UI, logging, status providers) reason about
/// "connected vs not" without per-manager casts.
public enum BleConnectionStatus: String {
    case disconnected = "Disconnected"
    case scanning     = "Scanning"
    case connecting   = "Connecting"
    case discovering  = "Discovering"
    case connected    = "Connected"
    case unauthorized = "Unauthorized"
    case poweredOff   = "Bluetooth Off"
}
