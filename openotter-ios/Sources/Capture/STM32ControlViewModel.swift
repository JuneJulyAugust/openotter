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

    // ESC Telemetry
    @Published var escStatus: ESCBleStatus = .disconnected
    @Published var escTelemetry: ESCTelemetry?
    @Published var escDeviceName: String = "Unknown"

    // ToF (FE60)
    @Published var tofFrame: TofFrame?
    @Published var tofState: TofState = .unknown
    @Published var tofScanHz: UInt8 = 0
    @Published var tofLastError: UInt8 = 0
    @Published var rearSafetyEvent: FirmwareSafetyEvent?
    @Published private var rearSafetyReceivedAt: Date?
    /// Defaults match firmware Init: 1×1 / LONG / 33 ms.
    @Published var tofConfig = TofConfig(layout: 1, distMode: 3, budgetUs: 33_000)

    // MARK: - Private

    private let bleManager = STM32BleManager.shared
    private let escManager = ESCBleManager.shared
    private let tofService = STM32TofService.shared
    private var cancellables = Set<AnyCancellable>()

    /// Debounce timer: waits for picker scroll to settle before sending.
    private var debounceTimer: Timer?
    /// Keepalive timer: re-sends current values every 500ms to prevent the
    /// firmware's 1500ms safety timeout from triggering neutral.
    private var keepaliveTimer: Timer?
    /// Single debounce window for any ToF picker/slider change — collapses
    /// rapid touches into one FE61 write.
    private var tofConfigTimer: Timer?

    // MARK: - Timing Constants

    /// Wait this long after the last picker change before sending. Prevents
    /// flooding BLE with every intermediate scroll position.
    private static let debounceInterval: TimeInterval = 0.25
    /// Must be well under the firmware's BLE_SAFETY_TIMEOUT_MS (1500ms).
    private static let keepaliveInterval: TimeInterval = 0.5

    // MARK: - PWM Constants (must match firmware ble_app.h)

    /// PWM range: 1000µs (min) to 2000µs (max), 1500µs = neutral
    private static let pwmMin: Int16 = 1000
    private static let pwmMax: Int16 = 2000
    private static let pwmNeutral: Int16 = 1500

    // MARK: - Init

    init() {
        setupSubscriptions()
        bleManager.start()   // idempotent — no-op if already connected
        escManager.start()   // idempotent — no-op if already connected
        // Manual control unconditionally re-arms Drive: if the prior
        // self-driving session left the firmware in Park, throttle commands
        // would otherwise be silently dropped to neutral by the firmware.
        bleManager.setOperatingMode(.drive)
    }

    deinit {
        debounceTimer?.invalidate()
        keepaliveTimer?.invalidate()
        tofConfigTimer?.invalidate()
        // Shared singletons are not stopped — they outlive this viewmodel
    }

    // MARK: - Public API

    /// Called on every picker value change. Updates state immediately for UI
    /// feedback but debounces the actual BLE transmission.
    func updateSteering(_ value: Float) {
        steering = value
        scheduleSend()
    }

    func updateThrottle(_ value: Float) {
        throttle = value
        scheduleSend()
    }

    /// Sends neutral immediately and restarts keepalive at neutral.
    func resetToNeutral() {
        steering = 0
        throttle = 0
        sendNow()
    }

    func reconnect() {
        bleManager.stop()
        bleManager.start()
    }

    // MARK: - ToF API

    func setTofLayout(_ layout: UInt8) {
        tofConfig.layout = layout
        tofConfig.budgetUs = TofConfig.clampBudget(tofConfig.budgetUs,
                                                   layout: layout,
                                                   distMode: tofConfig.distMode)
        scheduleTofSend()
    }

    func setTofDistMode(_ mode: UInt8) {
        tofConfig.distMode = mode
        tofConfig.budgetUs = TofConfig.clampBudget(tofConfig.budgetUs,
                                                   layout: tofConfig.layout,
                                                   distMode: mode)
        scheduleTofSend()
    }

    func setTofBudgetMs(_ ms: UInt32) {
        tofConfig.budgetUs = TofConfig.clampBudget(ms * 1000,
                                                   layout: tofConfig.layout,
                                                   distMode: tofConfig.distMode)
        scheduleTofSend()
    }

    private func scheduleTofSend() {
        tofConfigTimer?.invalidate()
        tofConfigTimer = Timer.scheduledTimer(
            withTimeInterval: Self.debounceInterval,
            repeats: false
        ) { [weak self] _ in
            self?.sendTofConfig()
        }
    }

    private func sendTofConfig() {
        tofService.sendConfig(layout: tofConfig.layout,
                              distMode: tofConfig.distMode,
                              budgetUs: tofConfig.budgetUs)
    }

    // MARK: - Send Logic

    /// Resets the debounce window. The command is sent only after the picker
    /// has been idle for `debounceInterval` — i.e. finger has left the wheel.
    private func scheduleSend() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: Self.debounceInterval,
            repeats: false
        ) { [weak self] _ in
            self?.sendNow()
        }
    }

    /// Transmits current steering + throttle once, then restarts the keepalive
    /// so the firmware's safety timeout never fires.
    private func sendNow() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        let steeringUs = Self.toPulseWidth(steering)
        let throttleUs = Self.toPulseWidth(throttle)
        let velocityMmPerSec = Int16(max(-32_000.0, min(32_000.0, currentSignedVelocityMps() * 1000.0)))
        bleManager.sendCommand(steeringMicros: steeringUs,
                               throttleMicros: throttleUs,
                               velocityMmPerSec: velocityMmPerSec)
        restartKeepalive()
    }

    /// Ground speed reported by the ESC, forwarded to the firmware reverse
    /// safety supervisor.
    ///
    /// The ESC decodes eRPM via `signed32BE`, so `speedMps` preserves sign
    /// when the firmware actually reports direction. In practice some ESC
    /// firmwares emit unsigned magnitude; in that case the firmware
    /// supervisor's velocity-sign gate will not fire for pure coast-backward
    /// (throttle=0 rolling downhill) and falls back to the commanded-throttle
    /// gate (spec §3.2 union). Either way we never send a wrong-signed value.
    private func currentSignedVelocityMps() -> Float {
        return Float(escTelemetry?.speedMps ?? 0.0)
    }
    /// Schedules a repeating timer that re-sends current values every 500ms.
    /// Resets after every explicit send to avoid double-firing.
    private func restartKeepalive() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = Timer.scheduledTimer(
            withTimeInterval: Self.keepaliveInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self, self.status == .connected else { return }
            let steeringUs = Self.toPulseWidth(self.steering)
            let throttleUs = Self.toPulseWidth(self.throttle)
            let velocityMmPerSec = Int16(max(-32_000.0,
                                             min(32_000.0,
                                                 self.currentSignedVelocityMps() * 1000.0)))
            self.bleManager.sendCommand(steeringMicros: steeringUs,
                                        throttleMicros: throttleUs,
                                        velocityMmPerSec: velocityMmPerSec)
        }
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

        bleManager.$lastSafetyEvent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.rearSafetyEvent = event
                self?.rearSafetyReceivedAt = event.map { _ in Date() }
            }
            .store(in: &cancellables)

        escManager.$status
            .receive(on: DispatchQueue.main)
            .assign(to: &$escStatus)

        escManager.$telemetry
            .receive(on: DispatchQueue.main)
            .assign(to: &$escTelemetry)

        escManager.$deviceName
            .receive(on: DispatchQueue.main)
            .assign(to: &$escDeviceName)

        tofService.$latestFrame
            .receive(on: DispatchQueue.main)
            .assign(to: &$tofFrame)

        tofService.$state
            .receive(on: DispatchQueue.main)
            .assign(to: &$tofState)

        tofService.$scanHz
            .receive(on: DispatchQueue.main)
            .assign(to: &$tofScanHz)

        tofService.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$tofLastError)
    }

    /// Maps a normalized [-1, +1] control value to a PWM pulse width [1000, 2000] µs.
    private static func toPulseWidth(_ normalized: Float) -> Int16 {
        let clamped = max(-1.0, min(1.0, normalized))
        let us = Float(pwmNeutral) + clamped * Float(pwmMax - pwmNeutral)
        return Int16(us)
    }

    func rearSafetyPresentation(now: Date = Date()) -> RearSafetyPresentation? {
        guard let rearSafetyEvent, let rearSafetyReceivedAt else { return nil }
        return RearSafetyPresentation(
            event: rearSafetyEvent,
            receivedAt: rearSafetyReceivedAt,
            now: now,
            currentSpeedMps: Float(escTelemetry?.speedMps ?? 0.0)
        )
    }
}
