import Foundation
import Combine

class STM32ControlViewModel: ObservableObject {

    // MARK: - Published State

    @Published var status: STM32BleStatus = .disconnected
    @Published var deviceName: String = "Unknown"
    @Published var rssi: Int = 0
    @Published var commandsSent: Int = 0

    /// Steering: -1.0 (full left) to +1.0 (full right), 0 = center
    @Published var steering: Float = 0.0
    /// Throttle: -1.0 (full reverse) to +1.0 (full forward), 0 = neutral
    @Published var throttle: Float = 0.0

    // MARK: - Private

    private let bleManager = STM32BleManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - PWM Constants (must match firmware ble_app.h)

    /// PWM range: 1000µs (min) to 2000µs (max), 1500µs = neutral
    private static let pwmMin: Int16 = 1000
    private static let pwmMax: Int16 = 2000
    private static let pwmNeutral: Int16 = 1500

    // MARK: - Init

    init() {
        setupSubscriptions()
        bleManager.start()
    }

    deinit {
        bleManager.stop()
    }

    // MARK: - Public API

    func updateSteering(_ value: Float) {
        steering = value
        sendCommand()
    }

    func updateThrottle(_ value: Float) {
        throttle = value
        sendCommand()
    }

    func resetToNeutral() {
        steering = 0
        throttle = 0
        sendCommand()
    }

    func reconnect() {
        bleManager.stop()
        bleManager.start()
    }

    // MARK: - Private

    private func setupSubscriptions() {
        bleManager.$status
            .receive(on: DispatchQueue.main)
            .assign(to: &$status)

        bleManager.$deviceName
            .receive(on: DispatchQueue.main)
            .assign(to: &$deviceName)

        bleManager.$rssi
            .receive(on: DispatchQueue.main)
            .assign(to: &$rssi)

        bleManager.$commandsSent
            .receive(on: DispatchQueue.main)
            .assign(to: &$commandsSent)
    }

    /// Maps a normalized [-1, +1] control value to a PWM pulse width [1000, 2000] µs.
    private static func toPulseWidth(_ normalized: Float) -> Int16 {
        let clamped = max(-1.0, min(1.0, normalized))
        let us = Float(pwmNeutral) + clamped * Float(pwmMax - pwmNeutral)
        return Int16(us)
    }

    private func sendCommand() {
        let steeringUs = Self.toPulseWidth(steering)
        let throttleUs = Self.toPulseWidth(throttle)
        bleManager.sendCommand(steeringMicros: steeringUs, throttleMicros: throttleUs)
    }
}
