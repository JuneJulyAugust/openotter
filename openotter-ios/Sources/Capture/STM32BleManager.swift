import Foundation
import CoreBluetooth
import Combine
import Darwin

/// Backwards-compatible alias. `BleConnectionStatus` is the canonical
/// type shared across all BLE managers. Existing call sites that
/// reference `STM32BleStatus` keep compiling without change.
public typealias STM32BleStatus = BleConnectionStatus

enum STM32ModeTransitionAction: Equatable {
    case setDebugStreamingEnabled(Bool)
    case armDebugStreamingAfterModeWriteAck
    case writeMode(OperatingMode)
}

struct STM32ModeTransitionPolicy {
    static func startActions(for mode: OperatingMode) -> [STM32ModeTransitionAction] {
        switch mode {
        case .debug:
            return [.armDebugStreamingAfterModeWriteAck,
                    .writeMode(.debug)]
        case .drive:
            return [.setDebugStreamingEnabled(false),
                    .writeMode(.drive)]
        case .park:
            return [.setDebugStreamingEnabled(false),
                    .writeMode(.park)]
        }
    }

    static func shouldEnableDebugStreamingAfterModeAck(pendingEnable: Bool,
                                                       requestedMode: OperatingMode,
                                                       writeSucceeded: Bool) -> Bool {
        pendingEnable && requestedMode == .debug && writeSucceeded
    }
}

struct STM32DiscoveryPolicy {
    static func matchReason(cachedName: String,
                            advertisedName: String,
                            peripheralID: UUID,
                            rememberedPeripheralID: String?,
                            advertisedServiceUUIDs: [String] = [],
                            acceptBlueNRGFallback: Bool = false) -> String? {
        if cachedName.range(of: "OPENOTTER", options: .caseInsensitive) != nil {
            return "cached OPENOTTER name"
        }
        if advertisedName.range(of: "OPENOTTER", options: .caseInsensitive) != nil {
            return "advertised OPENOTTER name"
        }
        if rememberedPeripheralID == peripheralID.uuidString {
            return "remembered peripheral"
        }
        if advertisedServiceUUIDs.contains("FE40") || advertisedServiceUUIDs.contains("FE60") {
            return "advertised OpenOtter service"
        }
        if acceptBlueNRGFallback &&
            (cachedName.range(of: "BLUENRG", options: .caseInsensitive) != nil ||
             advertisedName.range(of: "BLUENRG", options: .caseInsensitive) != nil) {
            return "manual BlueNRG fallback"
        }
        return nil
    }

    static func isTargetPeripheral(cachedName: String,
                                   advertisedName: String,
                                   peripheralID: UUID,
                                   rememberedPeripheralID: String?,
                                   advertisedServiceUUIDs: [String] = [],
                                   acceptBlueNRGFallback: Bool = false) -> Bool {
        matchReason(cachedName: cachedName,
                    advertisedName: advertisedName,
                    peripheralID: peripheralID,
                    rememberedPeripheralID: rememberedPeripheralID,
                    advertisedServiceUUIDs: advertisedServiceUUIDs,
                    acceptBlueNRGFallback: acceptBlueNRGFallback) != nil
    }

    static func scanOptions(allowDuplicates: Bool) -> [String: Any] {
        guard allowDuplicates else { return [:] }
        return [CBCentralManagerScanOptionAllowDuplicatesKey: true]
    }

    static func shouldTimeoutConnection(status: STM32BleStatus) -> Bool {
        status == .connecting || status == .discovering
    }

    static func shouldTryRememberedPeripheralOnScanTimeout(hasRememberedPeripheral: Bool,
                                                           status: STM32BleStatus) -> Bool {
        hasRememberedPeripheral && status == .scanning
    }

    static func shouldUseRememberedPeripheralFastPath() -> Bool {
        /*
         * STM32/BlueNRG can reset while iOS keeps a stale CBPeripheral/GATT
         * cache. Require a fresh advertisement before connecting; the
         * remembered ID is still used in didDiscover to match nameless ads.
         */
        false
    }

    static func shouldForgetRememberedPeripheralAfterConnectionTimeout(timedOutPeripheralID: String?,
                                                                       rememberedPeripheralID: String?) -> Bool {
        guard let timedOutPeripheralID, let rememberedPeripheralID else { return false }
        return timedOutPeripheralID == rememberedPeripheralID
    }

    static func shouldForgetRememberedPeripheralAfterDisconnect(errorDescription: String?) -> Bool {
        guard let errorDescription else { return false }
        return errorDescription.contains("CBErrorDomain Code=6") ||
            errorDescription.localizedCaseInsensitiveContains("timed out unexpectedly")
    }

    static func shouldResetCentralForManualReconnect() -> Bool {
        true
    }

    static func shouldResetCentralAfterScanTimeout(scanAttemptCount: UInt32,
                                                   hasRememberedPeripheral: Bool) -> Bool {
        hasRememberedPeripheral || (scanAttemptCount > 0 && scanAttemptCount % 3 == 0)
    }

    static func shouldAcceptCoreBluetoothCallback(isCurrentObject: Bool) -> Bool {
        isCurrentObject
    }
}

struct STM32BleDebugTrace {
    private(set) var events: [String] = []
    var limit: Int = 6

    mutating func append(_ event: String) -> String {
        events.append(event)
        let maxEvents = max(1, limit)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        return events.joined(separator: "\n--\n")
    }
}

struct STM32BleConsoleLogPolicy {
    static func shouldLog(event: String, sequence: UInt32) -> Bool {
        if event == "ignored advertisement" {
            return sequence % 10 == 0
        }
        return true
    }
}

/// Manages CoreBluetooth connection to the STM32 OPENOTTER-MCP BLE peripheral.
/// Sends steering + throttle commands as packed int16_t pairs (4 bytes).
public class STM32BleManager: NSObject, ObservableObject, OperatingModeReceiving {

    /// Shared singleton — only one connection to OPENOTTER-MCP may exist at a time.
    public static let shared = STM32BleManager()

    // MARK: - Published State

    @Published public var status: STM32BleStatus = .disconnected
    @Published public var deviceName: String = "Unknown"
    @Published public var rssi: Int = 0
    @Published public var commandsSent: Int = 0
    @Published public var lastSafetyEvent: FirmwareSafetyEvent? = nil
    @Published public var debugSummary: String = "BLE manager created"

    // MARK: - BLE UUIDs (must match firmware ble_app.h)

    /// Custom service: 0xFE40
    private let controlServiceUUID = CBUUID(string: "FE40")
    /// Write characteristic: 0xFE41 — receives [int16_t steering, int16_t throttle]
    private let commandCharUUID = CBUUID(string: "FE41")
    /// Notify characteristic: 0xFE42 — heartbeat/status from firmware
    private let statusCharUUID = CBUUID(string: "FE42")
    /// Notify characteristic: 0xFE43 — safety event
    private let safetyCharUUID = CBUUID(string: "FE43")
    /// Write characteristic: 0xFE44 — mode
    private let modeCharUUID = CBUUID(string: "FE44")

    /// ToF service: 0xFE60
    private let tofServiceUUID    = CBUUID(string: "FE60")
    private let tofConfigCharUUID = CBUUID(string: "FE61")
    private let tofFrameCharUUID  = CBUUID(string: "FE62")
    private let tofStatusCharUUID = CBUUID(string: "FE63")

    // MARK: - Private

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?
    private var safetyChar: CBCharacteristic?
    private var modeChar: CBCharacteristic?

    private var tofConfigChar: CBCharacteristic?
    private var tofFrameChar: CBCharacteristic?
    private var tofStatusChar: CBCharacteristic?
    private var safetyEventGate = FirmwareSafetyEventGate()
    private var requestedOperatingMode: OperatingMode = .drive
    private var enableDebugStreamingAfterModeAck = false
    private var shouldAutoReconnect = true
    private var connectionAttemptID: UInt64 = 0
    private var scanAttemptID: UInt64 = 0
    private var scanAttemptCount: UInt32 = 0
    private var manualBlueNRGFallbackUntil: Date?
    private var debugTrace = STM32BleDebugTrace()
    private var debugEventSequence: UInt32 = 0

    private let targetDeviceName = "OPENOTTER-MCP"
    private let rememberedPeripheralIDKey = "openotter.stm32.peripheralID"

    // MARK: - Init

    public override init() {
        super.init()
        STM32TofService.shared.onStreamStale = { [weak self] detail in
            self?.handleTofStreamStale(detail: detail)
        }
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    public func start() {
        start(allowDuplicates: false, preferRemembered: true)
    }

    private func start(allowDuplicates: Bool, preferRemembered: Bool) {
        guard status == .disconnected else {
            updateDebug("start ignored", detail: "status \(status.rawValue)")
            return
        }
        guard centralManager.state == .poweredOn else {
            updateDebug("start waiting", detail: "central \(Self.centralStateLabel(centralManager.state))")
            return
        }
        shouldAutoReconnect = true
        if preferRemembered, connectRememberedPeripheralIfAvailable() {
            return
        }
        scan(allowDuplicates: allowDuplicates)
    }

    public func stop() {
        shouldAutoReconnect = false
        cancelConnectionTimeout()
        cancelScanTimeout()
        centralManager.stopScan()
        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanup()
    }

    public func reconnect() {
        shouldAutoReconnect = true
        manualBlueNRGFallbackUntil = Date().addingTimeInterval(15)
        cancelConnectionTimeout()
        cancelScanTimeout()
        centralManager.stopScan()
        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        let remembered = UserDefaults.standard.string(forKey: rememberedPeripheralIDKey)
        UserDefaults.standard.removeObject(forKey: rememberedPeripheralIDKey)
        if STM32DiscoveryPolicy.shouldResetCentralForManualReconnect() {
            cleanup()
            resetCentralManagerForFreshScan(
                reason: "manual refresh; forgot \(Self.shortID(remembered ?? "-"))")
        } else {
            cleanup()
            updateDebug("manual refresh",
                        detail: "forgot \(Self.shortID(remembered ?? "-")); fresh duplicate scan for 15s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.start(allowDuplicates: true, preferRemembered: false)
            }
        }
    }

    /// Push the firmware operating mode (FE44). Park additionally clears the
    /// cached BRAKE event so the UI overlay/alarm drops immediately, without
    /// waiting for the firmware's SAFE snapshot to round-trip. Drive only
    /// writes the byte — the firmware re-enables the supervisor in SAFE
    /// state on the mode-edge and broadcasts a SAFE snapshot itself.
    public func setOperatingMode(_ mode: OperatingMode) {
        requestedOperatingMode = mode
        let visibleEvent = safetyEventGate.setOperatingMode(mode)
        publishSafetyEvent(visibleEvent)

        applyOperatingModeTransition(mode)
    }

    private func applyOperatingModeTransition(_ mode: OperatingMode) {
        for action in STM32ModeTransitionPolicy.startActions(for: mode) {
            switch action {
            case .setDebugStreamingEnabled(let enabled):
                if !enabled {
                    enableDebugStreamingAfterModeAck = false
                }
                STM32TofService.shared.setDebugStreamingEnabled(enabled)
            case .armDebugStreamingAfterModeWriteAck:
                enableDebugStreamingAfterModeAck = true
            case .writeMode(let mode):
                let result = writeMode(mode)
                if mode == .debug,
                   enableDebugStreamingAfterModeAck,
                   result == .queuedWithoutResponse {
                    enableDebugStreamingAfterModeAck = false
                    STM32TofService.shared.setDebugStreamingEnabled(true)
                }
            }
        }
    }

    private enum ModeWriteResult: Equatable {
        case unavailable
        case queuedWithResponse
        case queuedWithoutResponse
    }

    @discardableResult
    private func writeMode(_ mode: OperatingMode) -> ModeWriteResult {
        guard let modeChar, let peripheral else { return .unavailable }
        let usesResponse = modeChar.properties.contains(.write)
        let writeType: CBCharacteristicWriteType = usesResponse ? .withResponse : .withoutResponse
        peripheral.writeValue(Data([mode.wireValue]), for: modeChar, type: writeType)
        return usesResponse ? .queuedWithResponse : .queuedWithoutResponse
    }

    private func handleModeWriteAck(succeeded: Bool) {
        if STM32ModeTransitionPolicy.shouldEnableDebugStreamingAfterModeAck(
            pendingEnable: enableDebugStreamingAfterModeAck,
            requestedMode: requestedOperatingMode,
            writeSucceeded: succeeded) {
            enableDebugStreamingAfterModeAck = false
            STM32TofService.shared.setDebugStreamingEnabled(true)
        } else if !succeeded || requestedOperatingMode != .debug {
            enableDebugStreamingAfterModeAck = false
        }
    }

    /// Send steering, throttle (pulse widths in µs) and measured velocity
    /// (mm/s, negative = reversing) to the STM32.
    public func sendCommand(steeringMicros: Int16,
                            throttleMicros: Int16,
                            velocityMmPerSec: Int16) {
        guard let commandChar, let peripheral else { return }

        var payload = Data(count: 6)
        payload.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: steeringMicros.littleEndian,
                           toByteOffset: 0, as: Int16.self)
            ptr.storeBytes(of: throttleMicros.littleEndian,
                           toByteOffset: 2, as: Int16.self)
            ptr.storeBytes(of: velocityMmPerSec.littleEndian,
                           toByteOffset: 4, as: Int16.self)
        }

        let writeType: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse)
                ? .withoutResponse : .withResponse
        peripheral.writeValue(payload, for: commandChar, type: writeType)

        DispatchQueue.main.async { self.commandsSent += 1 }
    }

    // MARK: - Private

    private func cleanup() {
        peripheral = nil
        commandChar = nil
        statusChar = nil
        safetyChar = nil
        modeChar = nil
        tofConfigChar = nil
        tofFrameChar = nil
        tofStatusChar = nil
        enableDebugStreamingAfterModeAck = false
        safetyEventGate.resetConnection()
        publishSafetyEvent(safetyEventGate.lastSafetyEvent)
        STM32TofService.shared.setDebugStreamingEnabled(false)
        STM32TofService.shared.detach()
        status = .disconnected
    }

    private func scan(allowDuplicates: Bool = false) {
        scanAttemptCount &+= 1
        cancelScanTimeout()
        status = .scanning
        updateDebug("scan \(scanAttemptCount)",
                    detail: allowDuplicates ? "duplicates enabled" : "duplicates disabled")
        /* Scan without service filter — BlueNRG 16-bit UUIDs are often
         * not included in the iOS service-UUID advertisement cache, so
         * a filtered scan silently misses the device.  We match by name
         * in didDiscover instead. */
        centralManager.scanForPeripherals(
            withServices: nil,
            options: STM32DiscoveryPolicy.scanOptions(allowDuplicates: allowDuplicates))
        scheduleScanTimeout()
    }

    private func connectRememberedPeripheralIfAvailable() -> Bool {
        guard let idString = UserDefaults.standard.string(forKey: rememberedPeripheralIDKey),
              let uuid = UUID(uuidString: idString) else {
            return false
        }
        guard STM32DiscoveryPolicy.shouldUseRememberedPeripheralFastPath() else {
            updateDebug("remembered fast path skipped",
                        detail: "\(Self.shortID(idString)); waiting for fresh advertisement")
            return false
        }
        if let connected = centralManager
            .retrieveConnectedPeripherals(withServices: [controlServiceUUID, tofServiceUUID])
            .first(where: { $0.identifier == uuid }) {
            updateDebug("connect remembered", detail: "system-connected \(Self.shortID(idString))")
            connect(connected, advertisedName: nil, rssi: nil)
            return true
        }
        guard let remembered = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first else {
            updateDebug("remembered unavailable",
                        detail: "\(Self.shortID(idString)); scanning advertisements")
            return false
        }
        updateDebug("connect remembered", detail: "identifier \(Self.shortID(idString))")
        connect(remembered, advertisedName: nil, rssi: nil)
        return true
    }

    private func connect(_ peripheral: CBPeripheral,
                         advertisedName: String?,
                         rssi: NSNumber?) {
        centralManager.stopScan()
        cancelScanTimeout()
        remember(peripheral)
        self.peripheral = peripheral
        self.deviceName = advertisedName?.isEmpty == false ? advertisedName! : (peripheral.name ?? targetDeviceName)
        if let rssi {
            self.rssi = rssi.intValue
        }
        status = .connecting
        updateDebug("connecting",
                    detail: "\(self.deviceName) id \(Self.shortID(peripheral.identifier.uuidString))")
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        scheduleConnectionTimeout()
    }

    private func remember(_ peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: rememberedPeripheralIDKey)
    }

    private func scheduleConnectionTimeout() {
        connectionAttemptID &+= 1
        let attemptID = connectionAttemptID
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            self?.handleConnectionTimeout(attemptID: attemptID)
        }
    }

    private func cancelConnectionTimeout() {
        connectionAttemptID &+= 1
    }

    private func scheduleScanTimeout() {
        scanAttemptID &+= 1
        let attemptID = scanAttemptID
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            self?.handleScanTimeout(attemptID: attemptID)
        }
    }

    private func cancelScanTimeout() {
        scanAttemptID &+= 1
    }

    private func handleScanTimeout(attemptID: UInt64) {
        guard attemptID == scanAttemptID, status == .scanning else { return }
        let hasRememberedPeripheral = UserDefaults.standard.string(forKey: rememberedPeripheralIDKey) != nil
        if STM32DiscoveryPolicy.shouldTryRememberedPeripheralOnScanTimeout(
            hasRememberedPeripheral: hasRememberedPeripheral,
            status: status),
           connectRememberedPeripheralIfAvailable() {
            manualBlueNRGFallbackUntil = Date().addingTimeInterval(20)
            return
        }
        if hasRememberedPeripheral {
            manualBlueNRGFallbackUntil = Date().addingTimeInterval(20)
        }
        if STM32DiscoveryPolicy.shouldResetCentralAfterScanTimeout(
            scanAttemptCount: scanAttemptCount,
            hasRememberedPeripheral: hasRememberedPeripheral) {
            manualBlueNRGFallbackUntil = Date().addingTimeInterval(20)
            UserDefaults.standard.removeObject(forKey: rememberedPeripheralIDKey)
            resetCentralManagerForFreshScan(
                reason: "scan timeout \(scanAttemptCount); fresh duplicate scan")
            return
        }
        updateDebug("scan timeout",
                    detail: hasRememberedPeripheral
                    ? "enabling BlueNRG fallback and duplicate scan"
                    : "continuing strict duplicate scan")
        centralManager.stopScan()
        scan(allowDuplicates: true)
    }

    private func handleConnectionTimeout(attemptID: UInt64) {
        guard attemptID == connectionAttemptID,
              STM32DiscoveryPolicy.shouldTimeoutConnection(status: status) else {
            return
        }
        let timedOutPeripheralID = peripheral?.identifier.uuidString
        let rememberedPeripheralID = UserDefaults.standard.string(forKey: rememberedPeripheralIDKey)
        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanup()
        if shouldAutoReconnect {
            manualBlueNRGFallbackUntil = Date().addingTimeInterval(20)
            if STM32DiscoveryPolicy.shouldForgetRememberedPeripheralAfterConnectionTimeout(
                timedOutPeripheralID: timedOutPeripheralID,
                rememberedPeripheralID: rememberedPeripheralID) {
                UserDefaults.standard.removeObject(forKey: rememberedPeripheralIDKey)
                updateDebug("connect timeout",
                            detail: "forgot stale remembered \(Self.shortID(timedOutPeripheralID ?? "-")); resetting central")
                resetCentralManagerForFreshScan(reason: "remembered timeout")
                return
            }
            updateDebug("connect timeout", detail: "retrying duplicate scan")
            scan(allowDuplicates: true)
        }
    }

    private func resetCentralManagerForFreshScan(reason: String) {
        cancelConnectionTimeout()
        cancelScanTimeout()
        centralManager.stopScan()
        peripheral = nil
        commandChar = nil
        statusChar = nil
        safetyChar = nil
        modeChar = nil
        tofConfigChar = nil
        tofFrameChar = nil
        tofStatusChar = nil
        status = .disconnected
        updateDebug("central reset", detail: reason)
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    private func handleTofStreamStale(detail: String) {
        guard status == .connected, requestedOperatingMode == .debug else { return }
        updateDebug("tof stream stale", detail: detail)
        reconnect()
    }

    private func updateDebug(_ event: String, detail: String = "") {
        debugEventSequence &+= 1
        let remembered = UserDefaults.standard.string(forKey: rememberedPeripheralIDKey).map(Self.shortID) ?? "-"
        let fallback: String
        if let manualBlueNRGFallbackUntil, manualBlueNRGFallbackUntil > Date() {
            fallback = "on"
        } else {
            fallback = "off"
        }
        let lines = [
            "#\(debugEventSequence) \(event)",
            "central \(Self.centralStateLabel(centralManager?.state ?? .unknown)) status \(status.rawValue)",
            "remembered \(remembered) scans \(scanAttemptCount) fallback \(fallback)",
            detail
        ].filter { !$0.isEmpty }
        let text = debugTrace.append(lines.joined(separator: "\n"))
        if Thread.isMainThread {
            debugSummary = text
        } else {
            DispatchQueue.main.async { self.debugSummary = text }
        }
        if STM32BleConsoleLogPolicy.shouldLog(event: event, sequence: debugEventSequence) {
            Self.writeConsoleLog(lines.joined(separator: " | "))
        }
    }

    private static func writeConsoleLog(_ text: String) {
        let line = "[STM32 BLE] \(text)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
        fflush(stderr)
    }

    private static func centralStateLabel(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "off"
        case .poweredOn: return "on"
        @unknown default: return "future"
        }
    }

    private static func advertisedServiceUUIDStrings(from advertisementData: [String: Any]) -> [String] {
        let keys = [
            CBAdvertisementDataServiceUUIDsKey,
            CBAdvertisementDataOverflowServiceUUIDsKey,
            CBAdvertisementDataSolicitedServiceUUIDsKey
        ]
        return keys
            .flatMap { advertisementData[$0] as? [CBUUID] ?? [] }
            .map { $0.uuidString.uppercased() }
    }

    private static func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }
}

// MARK: - CBCentralManagerDelegate

extension STM32BleManager: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard STM32DiscoveryPolicy.shouldAcceptCoreBluetoothCallback(
            isCurrentObject: central === centralManager) else {
            return
        }
        switch central.state {
        case .poweredOn:
            updateDebug("central powered on")
            if status == .disconnected { start() }
        case .poweredOff:
            shouldAutoReconnect = false
            cancelConnectionTimeout()
            cancelScanTimeout()
            status = .poweredOff
            updateDebug("central powered off")
        case .unauthorized:
            shouldAutoReconnect = false
            cancelConnectionTimeout()
            cancelScanTimeout()
            status = .unauthorized
            updateDebug("central unauthorized")
        default:
            cancelConnectionTimeout()
            cancelScanTimeout()
            status = .disconnected
            updateDebug("central \(Self.centralStateLabel(central.state))")
        }
    }

    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any],
                               rssi RSSI: NSNumber) {
        guard STM32DiscoveryPolicy.shouldAcceptCoreBluetoothCallback(
            isCurrentObject: central === centralManager) else {
            return
        }
        // After a prior connection iOS caches the GAP device name
        // ("BlueNRG") as peripheral.name, hiding the advertising
        // local name ("OPENOTTER-MCP").  Check both sources.
        let cachedName = peripheral.name ?? ""
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        let advertisedServices = Self.advertisedServiceUUIDStrings(from: advertisementData)
        let servicesLabel = advertisedServices.isEmpty ? "-" : advertisedServices.joined(separator: ",")

        let rememberedID = UserDefaults.standard.string(forKey: rememberedPeripheralIDKey)
        let acceptsBlueNRGFallback = manualBlueNRGFallbackUntil.map { $0 > Date() } ?? false
        let matchReason = STM32DiscoveryPolicy.matchReason(
            cachedName: cachedName,
            advertisedName: advName,
            peripheralID: peripheral.identifier,
            rememberedPeripheralID: rememberedID,
            advertisedServiceUUIDs: advertisedServices,
            acceptBlueNRGFallback: acceptsBlueNRGFallback
        )

        let discoveryDetail = "cached \(cachedName.isEmpty ? "-" : cachedName) adv \(advName.isEmpty ? "-" : advName) rssi \(RSSI.intValue) id \(Self.shortID(peripheral.identifier.uuidString)) svc \(servicesLabel)"
        guard let matchReason else {
            updateDebug("ignored advertisement", detail: discoveryDetail)
            return
        }

        manualBlueNRGFallbackUntil = nil
        updateDebug("matched advertisement", detail: "\(matchReason)\n\(discoveryDetail)")
        connect(peripheral, advertisedName: advName.isEmpty ? cachedName : advName, rssi: RSSI)
    }

    public func centralManager(_ central: CBCentralManager,
                               didConnect peripheral: CBPeripheral) {
        guard STM32DiscoveryPolicy.shouldAcceptCoreBluetoothCallback(
            isCurrentObject: central === centralManager && peripheral === self.peripheral) else {
            return
        }
        cancelScanTimeout()
        status = .discovering
        updateDebug("connected", detail: "discovering services")
        // Discover all services — BlueNRG 16-bit UUIDs may not match
        // the iOS CBUUID filter after reconnection
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        guard STM32DiscoveryPolicy.shouldAcceptCoreBluetoothCallback(
            isCurrentObject: central === centralManager && peripheral === self.peripheral) else {
            return
        }
        cancelConnectionTimeout()
        cancelScanTimeout()
        let errorText = error.map { "\($0)" } ?? "nil"
        let shouldResetCentral =
            STM32DiscoveryPolicy.shouldForgetRememberedPeripheralAfterDisconnect(
                errorDescription: error.map { "\($0)" })
        let remembered = UserDefaults.standard.string(forKey: rememberedPeripheralIDKey)
        cleanup()
        updateDebug("disconnected", detail: errorText)
        guard shouldAutoReconnect else { return }
        manualBlueNRGFallbackUntil = Date().addingTimeInterval(20)
        if shouldResetCentral {
            UserDefaults.standard.removeObject(forKey: rememberedPeripheralIDKey)
            resetCentralManagerForFreshScan(
                reason: "disconnect timeout; forgot \(Self.shortID(remembered ?? "-"))")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.scan(allowDuplicates: true)
        }
    }

    public func centralManager(_ central: CBCentralManager,
                               didFailToConnect peripheral: CBPeripheral,
                               error: Error?) {
        guard STM32DiscoveryPolicy.shouldAcceptCoreBluetoothCallback(
            isCurrentObject: central === centralManager && peripheral === self.peripheral) else {
            return
        }
        cancelConnectionTimeout()
        cancelScanTimeout()
        let errorText = error.map { "\($0)" } ?? "nil"
        cleanup()
        updateDebug("connect failed", detail: errorText)
        guard shouldAutoReconnect else { return }
        manualBlueNRGFallbackUntil = Date().addingTimeInterval(20)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.scan(allowDuplicates: true)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension STM32BleManager: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverServices error: Error?) {
        guard STM32DiscoveryPolicy.shouldAcceptCoreBluetoothCallback(
            isCurrentObject: peripheral === self.peripheral) else {
            return
        }
        if let error {
            updateDebug("service discovery failed", detail: "\(error)")
        }
        guard let services = peripheral.services else { return }
        let serviceList = services.map { $0.uuid.uuidString }.joined(separator: ",")
        updateDebug("services discovered", detail: serviceList.isEmpty ? "-" : serviceList)
        for service in services {
            switch service.uuid {
            case controlServiceUUID:
                peripheral.discoverCharacteristics([commandCharUUID, statusCharUUID, safetyCharUUID, modeCharUUID], for: service)
            case tofServiceUUID:
                peripheral.discoverCharacteristics(
                    [tofConfigCharUUID, tofFrameCharUUID, tofStatusCharUUID], for: service)
            default:
                break
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        guard STM32DiscoveryPolicy.shouldAcceptCoreBluetoothCallback(
            isCurrentObject: peripheral === self.peripheral) else {
            return
        }
        if let error {
            updateDebug("characteristic discovery failed",
                        detail: "\(service.uuid.uuidString) \(error)")
        }
        guard let chars = service.characteristics else { return }
        let charList = chars.map { $0.uuid.uuidString }.joined(separator: ",")
        updateDebug("chars discovered", detail: "\(service.uuid.uuidString): \(charList)")

        switch service.uuid {
        case controlServiceUUID:
            for char in chars {
                switch char.uuid {
                case commandCharUUID:
                    commandChar = char
                case statusCharUUID:
                    statusChar = char
                    if char.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: char)
                    }
                case safetyCharUUID:
                    safetyChar = char
                    if char.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: char)
                    }
                    if char.properties.contains(.read) {
                        peripheral.readValue(for: char)
                    }
                case modeCharUUID:
                    modeChar = char
                    _ = safetyEventGate.setOperatingMode(requestedOperatingMode)
                    applyOperatingModeTransition(requestedOperatingMode)
                default:
                    break
                }
            }
            if commandChar != nil && modeChar != nil {
                cancelConnectionTimeout()
                status = .connected
                updateDebug("control ready", detail: "FE41/FE44 ready")
            }

        case tofServiceUUID:
            for char in chars {
                switch char.uuid {
                case tofConfigCharUUID: tofConfigChar = char
                case tofFrameCharUUID:  tofFrameChar  = char
                case tofStatusCharUUID: tofStatusChar = char
                default: break
                }
            }
            if let frame = tofFrameChar, let cfg = tofConfigChar, let st = tofStatusChar {
                STM32TofService.shared.attach(
                    peripheral: peripheral,
                    frameChar: frame,
                    configChar: cfg,
                    statusChar: st)
                updateDebug("tof ready", detail: "FE61/FE62/FE63 ready")
            }

        default:
            break
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard STM32DiscoveryPolicy.shouldAcceptCoreBluetoothCallback(
            isCurrentObject: peripheral === self.peripheral) else {
            return
        }
        switch characteristic.uuid {
        case tofFrameCharUUID:
            if let data = characteristic.value {
                STM32TofService.shared.handleFrameNotification(data)
            }
        case tofStatusCharUUID:
            if let data = characteristic.value {
                STM32TofService.shared.handleStatusNotification(data)
            }
        case statusCharUUID:
            // FE42 control-side status — no consumer yet.
            break
        case safetyCharUUID:
            guard let data = characteristic.value else { return }
            do {
                let ev = try FirmwareSafetyEvent(data: data)
                if safetyEventGate.lastSafetySeq == ev.seq &&
                   safetyEventGate.lastSafetyEvent == ev {
                    return
                }
                if let lastSafetySeq = safetyEventGate.lastSafetySeq,
                   ev.seq > lastSafetySeq + 1,
                   let safetyChar,
                   characteristic.properties.contains(.read) {
                    peripheral.readValue(for: safetyChar)
                }
                let visibleEvent = safetyEventGate.ingest(ev)
                publishSafetyEvent(visibleEvent)
            } catch {
                // Ignore malformed payloads; firmware should never send them.
            }
        default:
            break
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didReadRSSI RSSI: NSNumber,
                           error: Error?) {
        guard STM32DiscoveryPolicy.shouldAcceptCoreBluetoothCallback(
            isCurrentObject: peripheral === self.peripheral) else {
            return
        }
        rssi = RSSI.intValue
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard STM32DiscoveryPolicy.shouldAcceptCoreBluetoothCallback(
            isCurrentObject: peripheral === self.peripheral) else {
            return
        }
        let errStr = error.map { "\($0)" } ?? "nil"
        NSLog("[TOF] CCCD update \(characteristic.uuid) "
              + "isNotifying=\(characteristic.isNotifying) error=\(errStr)")
        if characteristic.uuid == tofFrameCharUUID || characteristic.uuid == tofStatusCharUUID {
            STM32TofService.shared.handleNotificationState(characteristic, error: error)
            updateDebug("tof notify \(characteristic.uuid.uuidString)",
                        detail: "isNotifying \(characteristic.isNotifying) error \(errStr)")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didWriteValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard STM32DiscoveryPolicy.shouldAcceptCoreBluetoothCallback(
            isCurrentObject: peripheral === self.peripheral) else {
            return
        }
        if characteristic.uuid == tofConfigCharUUID || characteristic.uuid == modeCharUUID {
            let errStr = error.map { "\($0)" } ?? "nil"
            NSLog("[TOF] write ack \(characteristic.uuid) error=\(errStr)")
        }
        if characteristic.uuid == modeCharUUID {
            updateDebug("mode write ack", detail: error.map { "\($0)" } ?? "\(requestedOperatingMode)")
            handleModeWriteAck(succeeded: error == nil)
        } else if characteristic.uuid == tofConfigCharUUID {
            STM32TofService.shared.handleConfigWriteAck(error: error)
        }
    }

    fileprivate func publishSafetyEvent(_ event: FirmwareSafetyEvent?) {
        if Thread.isMainThread {
            lastSafetyEvent = event
        } else {
            DispatchQueue.main.async { self.lastSafetyEvent = event }
        }
    }
}
