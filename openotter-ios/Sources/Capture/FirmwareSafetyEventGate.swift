import Foundation

struct FirmwareSafetyEventGate {
    private(set) var operatingMode: OperatingMode = .drive
    private(set) var lastSafetySeq: UInt32?
    private(set) var lastSafetyEvent: FirmwareSafetyEvent?

    mutating func setOperatingMode(_ mode: OperatingMode) -> FirmwareSafetyEvent? {
        operatingMode = mode
        if mode != .drive {
            lastSafetyEvent = nil
        }
        return lastSafetyEvent
    }

    mutating func ingest(_ event: FirmwareSafetyEvent) -> FirmwareSafetyEvent? {
        if operatingMode != .drive {
            rememberSequenceFence(event.seq)
            lastSafetyEvent = nil
            return nil
        }

        if let lastSeq = lastSafetySeq, event.seq <= lastSeq {
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

    private mutating func rememberSequenceFence(_ seq: UInt32) {
        guard let lastSeq = lastSafetySeq else {
            lastSafetySeq = seq
            return
        }
        if seq > lastSeq {
            lastSafetySeq = seq
        }
    }
}
