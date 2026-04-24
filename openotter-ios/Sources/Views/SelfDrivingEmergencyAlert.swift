import Foundation

struct SelfDrivingEmergencyAlert: Equatable {
    let title: String
    let detail: String
    let metricsLine: String
    let secondaryLine: String?

    static func current(
        forwardEvent: SafetySupervisorEvent?,
        forwardRecord: SafetyBrakeRecord?,
        rearPresentation: RearSafetyPresentation?
    ) -> SelfDrivingEmergencyAlert? {
        if let rearPresentation, rearPresentation.isBrake {
            return .init(
                title: "REAR EMERGENCY BRAKE",
                detail: rearPresentation.detail,
                metricsLine: rearPresentation.metricsLine,
                secondaryLine: rearPresentation.timingLine
            )
        }

        guard let forwardEvent else { return nil }
        return .init(
            title: "EMERGENCY BRAKE",
            detail: String(
                format: "Depth %.2fm (raw %.2fm)  |  Dcrit %.2fm  |  v %.2fm/s",
                forwardEvent.smoothedDepth,
                forwardEvent.rawDepth,
                forwardEvent.criticalDistance,
                forwardEvent.speed
            ),
            metricsLine: forwardRecord.map(SelfDrivingEmergencyAlert.triggerFullText)
                ?? "Forward safety brake engaged.",
            secondaryLine: forwardRecord.flatMap(SelfDrivingEmergencyAlert.stopFullText)
        )
    }

    private static func triggerFullText(_ triggerRecord: SafetyBrakeRecord) -> String {
        let trigger = triggerRecord.trigger
        let motor = trigger.motorSpeed.isNaN ? "—" : String(format: "%.2f m/s", trigger.motorSpeed)
        let arkit = trigger.arkitSpeed.isNaN ? "—" : String(format: "%.2f m/s", trigger.arkitSpeed)
        return String(
            format: "Trigger | t %.3fs | Depth %.2fm | v %.2fm/s | Dc %.2fm | Motor %@ | ARKit %@",
            trigger.timestamp,
            trigger.depth,
            trigger.speed,
            trigger.criticalDistance,
            motor,
            arkit
        )
    }

    private static func stopFullText(_ record: SafetyBrakeRecord) -> String? {
        guard let stop = record.stop else { return nil }
        let bumperGap = String(format: "%.2fm", stop.depth - 0.13)
        let elapsed = record.stoppingTimeS.map { String(format: "%.2fs", $0) } ?? "—"
        let decel = record.actualDecelMPS2.map { String(format: "%.2f m/s²", $0) } ?? "—"
        let brakingDistance = record.brakingDistanceM.map { String(format: "%.2fm", $0) } ?? "—"
        return String(
            format: "Stopped | t %.3fs | Δt %@ | Depth %.2fm | bumper gap %@ | actual decel %@ | braking dist %@",
            stop.timestamp,
            elapsed,
            stop.depth,
            bumperGap,
            decel,
            brakingDistance
        )
    }
}
