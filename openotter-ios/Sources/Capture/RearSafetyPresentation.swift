import Foundation

struct RearSafetyPresentation: Equatable {
    let title: String
    let statusText: String
    let detail: String
    let metricsLine: String
    let timingLine: String?
    let isBrake: Bool

    init(event: FirmwareSafetyEvent,
         receivedAt: Date,
         now: Date,
         currentSpeedMps: Float) {
        if event.state == .brake {
            self.title = "Rear Safety Brake"
            self.statusText = "BRAKE"
            self.isBrake = true
            self.detail = RearSafetyPresentation.brakeDetail(for: event)
            self.metricsLine = String(
                format: "Trig %.2fm  |  Dcrit %.2fm  |  v %.2fm/s",
                event.triggerDepthM,
                event.criticalDistanceM,
                event.latchedSpeedMps
            )
            self.timingLine = String(
                format: "Brake %.1fs  |  Current %.2fm/s",
                max(0.0, now.timeIntervalSince(receivedAt)),
                currentSpeedMps
            )
        } else {
            self.title = "Rear Path Clear"
            self.statusText = "SAFE"
            self.isBrake = false
            self.detail = "Reverse path clear. You can reverse again."
            self.metricsLine = "Reverse safety latch released."
            self.timingLine = nil
        }
    }

    private static func brakeDetail(for event: FirmwareSafetyEvent) -> String {
        let cause: String
        switch event.cause {
        case .obstacle:
            cause = "Obstacle"
        case .tofBlind:
            cause = "Sensor blind"
        case .frameGap:
            cause = "Frame gap"
        case .driverDead:
            cause = "Driver offline"
        case .none, .unknown:
            cause = "Safety stop"
        }

        if event.cause == .obstacle {
            return String(
                format: "%@ at %.2f m while critical distance was %.2f m.",
                cause,
                event.triggerDepthM,
                event.criticalDistanceM
            )
        }

        return "\(cause). Reverse throttle is blocked until the rear path is safe."
    }
}
