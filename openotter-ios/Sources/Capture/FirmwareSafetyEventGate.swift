import Foundation

struct FirmwareSafetyEventGate {
    private(set) var operatingMode: OperatingMode = .drive
    private(set) var lastSafetySeq: UInt32?
    private(set) var lastSafetyEvent: FirmwareSafetyEvent?

    mutating func setOperatingMode(_ mode: OperatingMode) -> FirmwareSafetyEvent? {
        operatingMode = mode
        if mode != .drive {
            lastSafetySeq = nil
            lastSafetyEvent = nil
        }
        return lastSafetyEvent
    }

    mutating func ingest(_ event: FirmwareSafetyEvent) -> FirmwareSafetyEvent? {
        if operatingMode != .drive {
            lastSafetySeq = event.seq
            lastSafetyEvent = nil
            return nil
        }

        if lastSafetySeq == event.seq && lastSafetyEvent == event {
            return lastSafetyEvent
        }

        lastSafetySeq = event.seq
        lastSafetyEvent = event
        return event
    }

    mutating func resetConnection() {
        lastSafetySeq = nil
        lastSafetyEvent = nil
    }
}
