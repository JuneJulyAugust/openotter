import Foundation
import Combine
import SwiftUI

/// Orchestrates all subsystems for autonomous operation.
final class SelfDrivingViewModel: ObservableObject {
    
    // MARK: - Subsystems
    
    @Published var poseModel = ARKitPoseViewModel()
    @Published var escManager = ESCBleManager()
    @Published var stm32Manager = STM32BleManager()
    
    // MARK: - State
    
    @Published var isStarted = false
    @Published var isAutonomous = false
    @Published var showMapManager = false
    
    // Manual/Auto overrides for UI feedback
    @Published var steering: Float = 0.0
    @Published var throttle: Float = 0.0
    
    // Control Loop
    private var controlTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Forward sub-system changes to our own objectWillChange if needed,
        // but SwiftUI @Published handles nested object changes if they are classes.
        // Actually, SwiftUI doesn't automatically observe nested @Published objects.
        // We'll use manual subscriptions to trigger updates.
        
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
        
        isStarted = true
        
        // Start Control Loop @ 10Hz
        controlTimer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.runControlLoop()
            }
    }
    
    func stop() {
        isStarted = false
        isAutonomous = false
        
        controlTimer?.cancel()
        controlTimer = nil
        
        poseModel.stop()
        escManager.stop()
        stm32Manager.stop()
        
        resetActuators()
    }
    
    func toggleAutonomous() {
        isAutonomous.toggle()
        if !isAutonomous {
            resetActuators()
        }
    }
    
    // MARK: - Control Loop
    
    private func runControlLoop() {
        guard isStarted && isAutonomous else { return }
        
        // 1. Inputs
        guard let pose = poseModel.currentPose else { return }
        let telemetry = escManager.telemetry
        
        // 2. Planning (Placeholder)
        let (targetSteering, targetThrottle) = simplePlanner(pose: pose, telemetry: telemetry)
        
        // 3. Actuation
        self.steering = targetSteering
        self.throttle = targetThrottle
        
        sendActuatorCommands(steering: targetSteering, throttle: targetThrottle)
    }
    
    private func simplePlanner(pose: PoseEntry, telemetry: ESCTelemetry?) -> (Float, Float) {
        // TODO: Implement actual path following or obstacle avoidance.
        // For now, stay stationary (zero steering, zero throttle).
        return (0.0, 0.0)
    }
    
    // MARK: - Helpers
    
    private func setupSubscriptions() {
        // Subscribe to children to ensure UI updates when they change.
        poseModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        escManager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        stm32Manager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }
    
    private func sendActuatorCommands(steering: Float, throttle: Float) {
        let sPWM = toPulseWidth(steering)
        let tPWM = toPulseWidth(throttle)
        stm32Manager.sendCommand(steeringMicros: sPWM, throttleMicros: tPWM)
    }
    
    private func resetActuators() {
        steering = 0
        throttle = 0
        stm32Manager.sendCommand(steeringMicros: 1500, throttleMicros: 1500)
    }
    
    private func toPulseWidth(_ normalized: Float) -> Int16 {
        let clamped = max(-1.0, min(1.0, normalized))
        return Int16(1500.0 + clamped * 500.0)
    }
}
