import Foundation
import Combine
import SwiftUI

/// Orchestrates all subsystems for autonomous operation.
final class SelfDrivingViewModel: ObservableObject {

    // MARK: - Subsystems

    @Published var poseModel = ARKitPoseViewModel()
    @Published var escManager = ESCBleManager.shared
    @Published var stm32Manager = STM32BleManager.shared

    // MARK: - Planner

    let orchestrator: PlannerOrchestrator

    // MARK: - Agent Runtime

    let agentRuntime: AgentRuntime
    let telegramGateway: TelegramGateway
    private let speech: SpeechOutput
    private var gatewayBridge: GatewayBridge?

    /// Active waypoints for map overlay (empty for constant speed mode).
    @Published var waypoints: [Waypoint] = []

    /// Target throttle for constant throttle planner. Adjustable from UI.
    @Published var targetThrottle: Float = 0.4

    // MARK: - Throttle Limits

    static let maxThrottle: Float = 1.0
    static let minThrottle: Float = -1.0

    // MARK: - State

    @Published var isStarted = false
    @Published var showMapManager = false

    // Manual/Auto overrides for UI feedback
    @Published var steering: Float = 0.0
    @Published var throttle: Float = 0.0

    // Control loop subscription — driven by ARKit pose updates, not a fixed timer.
    private var controlLoopSub: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    /// Keepalive timer: re-sends the last steering/throttle pair every 500ms
    /// so the firmware's 1500ms safety timeout never forces neutral while
    /// the planner is idle (e.g. waiting for a Telegram goal).
    private var keepaliveTimer: Timer?
    /// Must be well under the firmware's BLE_SAFETY_TIMEOUT_MS (1500ms).
    private static let keepaliveInterval: TimeInterval = 0.5

    init() {
        let orch = PlannerOrchestrator(
            planner: ConstantSpeedPlanner(),
            modeReceiver: STM32BleManager.shared
        )
        let speechOutput = SpeechOutput()

        let token = KeychainHelper.read(key: "telegram-bot-token") ?? ""
        let gw = TelegramGateway(token: token)
        gw.allowedChatIds = {
            guard let raw = KeychainHelper.read(key: "telegram-allowed-chats") else { return [] }
            return Set(raw.split(separator: ",").compactMap { Int64($0) })
        }()

        let interpreter = KeywordInterpreter()
        let dispatcher = ActionDispatcher(
            goalReceiver: orch,
            statusProvider: CarStatusProvider(),
            interpreter: interpreter
        )
        let rt = AgentRuntime(
            interpreter: interpreter,
            dispatcher: dispatcher,
            responseBuilder: ResponseBuilder(),
            speech: speechOutput
        )

        self.orchestrator = orch
        self.agentRuntime = rt
        self.telegramGateway = gw
        self.speech = speechOutput

        let bridge = GatewayBridge(runtime: rt, gateway: gw)
        self.gatewayBridge = bridge
        gw.delegate = bridge

        setupSubscriptions()
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }

        poseModel.start()
        escManager.start()
        stm32Manager.start()
        telegramGateway.startPolling()

        isStarted = true
        startKeepalive()

        poseModel.onFrameUpdate = { [weak self] pose, depth, speed in
            self?.runControlLoop(pose: pose, depth: depth, speed: speed)
        }
    }

    func stop() {
        isStarted = false

        orchestrator.reset()
        poseModel.onFrameUpdate = nil
        stopKeepalive()

        poseModel.stop()
        telegramGateway.stopPolling()

        resetActuators()
    }



    // MARK: - Control Loop

    private func runControlLoop(pose: PoseEntry, depth: Float?, speed: Double?) {
        guard isStarted else { return }

        let motorSpeed: Double? = {
            guard let tel = escManager.telemetry, abs(tel.speedMps) > 0.01 else { return nil }
            return tel.speedMps
        }()
        let arkitSpeed: Double? = {
            if let s = speed, abs(s) > 0.01 { return s }
            return nil
        }()

        // Dispatch to main thread to serialize with Telegram command handling.
        // Eliminates the data race: orchestrator.tick() (ARKit bg thread)
        // vs orchestrator.setGoal/reset() (MainActor from Telegram commands).
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isStarted else { return }

            let context = PlannerContext(
                pose: pose,
                currentThrottle: self.throttle,
                escTelemetry: self.escManager.telemetry,
                forwardDepth: depth,
                motorSpeedMps: motorSpeed,
                arkitSpeedMps: arkitSpeed,
                timestamp: pose.timestamp
            )

            let command = self.orchestrator.tick(context: context)
            // Forward the ESC/ARKit-reported speed as-is. If the ESC emits a
            // signed value, the firmware supervisor's velocity-sign gate will
            // arm on coast-backward; if unsigned, it falls back to the
            // commanded-throttle gate (spec §3.2 union). Do not overlay a
            // sign from `currentThrottle` — that double-negates when ESC
            // actually reports signed values.
            let signedSpeedMps: Double? = motorSpeed ?? arkitSpeed
            self.sendActuatorCommands(steering: command.steering, throttle: command.throttle,
                                      velocity: signedSpeedMps)
            self.steering = command.steering
            self.throttle = command.throttle
        }
    }

    // MARK: - Helpers

    private func setupSubscriptions() {
        poseModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        escManager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        stm32Manager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        orchestrator.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        agentRuntime.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        telegramGateway.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    private func sendActuatorCommands(steering: Float, throttle: Float, velocity: Double? = nil) {
        let sPWM = toPulseWidth(steering)
        let tPWM = toPulseWidth(throttle)
        let speed = velocity ?? self.escManager.telemetry?.speedMps ?? self.poseModel.arkitSpeedMps
        let v_mm_s = Int16(max(-32000.0, min(32000.0, speed * 1000.0)))
        stm32Manager.sendCommand(steeringMicros: sPWM,
                                 throttleMicros: tPWM,
                                 velocityMmPerSec: v_mm_s)
    }

    private func resetActuators() {
        steering = 0
        throttle = 0
        stm32Manager.sendCommand(steeringMicros: 1500,
                                 throttleMicros: 1500,
                                 velocityMmPerSec: 0)
    }

    /// Starts a repeating timer that re-sends the current steering/throttle
    /// at 500ms intervals. This prevents the firmware's 1500ms safety timeout
    /// from reverting to neutral while the planner is idle between pose updates.
    private func startKeepalive() {
        stopKeepalive()
        keepaliveTimer = Timer.scheduledTimer(
            withTimeInterval: Self.keepaliveInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self, self.isStarted,
                  self.stm32Manager.status == .connected else { return }
            self.sendActuatorCommands(steering: self.steering, throttle: self.throttle)
        }
    }

    private func stopKeepalive() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
    }

    private func toPulseWidth(_ normalized: Float) -> Int16 {
        let clamped = max(-1.0, min(1.0, normalized))
        return Int16(1500.0 + clamped * 500.0)
    }
}

// MARK: - Car Status Provider

/// Reads live telemetry from BLE singletons to answer /status queries.
private struct CarStatusProvider: StatusProviding {
    func currentStatus() -> String {
        let esc = ESCBleManager.shared
        let stm32 = STM32BleManager.shared
        var parts: [String] = []

        if esc.status == .connected, let tel = esc.telemetry {
            parts.append(String(format: "Speed %.1f m/s, %.1f V, %d RPM", tel.speedMps, tel.voltage, tel.rpm))
        } else {
            parts.append("ESC \(esc.status == .connected ? "connected" : "offline")")
        }

        parts.append("STM32 \(stm32.status == .connected ? "online" : "offline")")

        return parts.joined(separator: " | ")
    }
}
