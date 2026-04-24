import Foundation

/// High-level operator state. Park, Drive, and Debug are mutually exclusive
/// commitments shared by the iOS planner stack and the firmware supervisor:
///
///   - `.drive` — planner may issue motion; iOS forward supervisor and
///                firmware reverse supervisor are armed and may publish BRAKE
///                events.
///   - `.debug` — firmware debug streams are enabled and firmware reverse
///                supervisor is disarmed. Use only for bench bring-up.
///   - `.park`  — planner is idle; both supervisors are held disarmed; the
///                firmware drops any non-neutral throttle on the floor.
///                Stable terminal state — supervisors cannot re-fire on
///                residual coast-back motion.
///
/// `PlannerOrchestrator` is the source of truth. Subsystems that need to
/// observe transitions (BLE bridge, HUD) either subscribe to the published
/// `operatingMode` or implement `OperatingModeReceiving` to be pushed
/// synchronously on every transition.
public enum OperatingMode: Equatable, Hashable {
    case drive
    case debug
    case park

    var wireValue: UInt8 {
        switch self {
        case .drive: return 0
        case .debug: return 1
        case .park: return 2
        }
    }
}

/// Synchronous push channel for mode transitions. Implementations should be
/// idempotent: the orchestrator may push the same mode twice (e.g. a second
/// `setGoal` while already in Drive) and downstream effects (BLE writes,
/// UI clears) must be safe to repeat.
public protocol OperatingModeReceiving: AnyObject {
    func setOperatingMode(_ mode: OperatingMode)
}
