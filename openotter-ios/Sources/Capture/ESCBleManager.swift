import Foundation
import CoreBluetooth
import Combine

/// Backwards-compatible alias. `BleConnectionStatus` is the canonical
/// type shared across all BLE managers. Existing call sites that
/// reference `ESCBleStatus` keep compiling without change.
public typealias ESCBleStatus = BleConnectionStatus

public struct ESCTelemetry {
    public let rpm: Int
    public let speedMps: Double
    public let escTemperature: Double
    public let motorTemperature: Double
    public let voltage: Double
    public let updateFrequency: Double
    public let messageCount: Int
    public let timestamp: Date
}

public class ESCBleManager: NSObject, ObservableObject {

    /// Shared singleton — only one connection to the ESC peripheral may exist at a time.
    public static let shared = ESCBleManager()

    @Published public var status: ESCBleStatus = .disconnected
    @Published public var telemetry: ESCTelemetry?
    @Published public var deviceName: String = "Unknown"

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?

    private let targetDeviceName = "ESDM_4181FB"
    private let targetService = CBUUID(string: "AE3A")
    private let targetWrite = CBUUID(string: "AE3B")
    private let targetNotify = CBUUID(string: "AE3C")

    private var pollTimer: Timer?
    private var handshakeTimer: Timer?

    // Filtering and Frequency calculation
    private var rpmFilter = MovingAverageFilter(size: 4)
    private var lastPacketTimes: [Date] = []
    private let frequencyWindowSize = 10
    public var messageCount = 0

    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    public func start() {
        guard status == .disconnected else { return }  // already running
        guard centralManager.state == .poweredOn else { return }
        scan()
    }

    public func stop() {
        cancelTimers()
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        status = .disconnected
    }

    private func scan() {
        status = .scanning
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    private func cancelTimers() {
        pollTimer?.invalidate()
        pollTimer = nil
        handshakeTimer?.invalidate()
        handshakeTimer = nil
    }

    private func preferredWriteType(for characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        if characteristic.properties.contains(.write) {
            return .withResponse
        }
        if characteristic.properties.contains(.writeWithoutResponse) {
            return .withoutResponse
        }
        return .withResponse
    }

    private func startHandshake() {
        cancelTimers()
        let initCommand: [UInt8] = [0x02, 0x01, 0x00, 0x00, 0x00, 0x03]
        var count = 0
        let type = writeChar.flatMap { preferredWriteType(for: $0) } ?? .withResponse

        handshakeTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self, let p = self.peripheral, let char = self.writeChar else { return }
            p.writeValue(Data(initCommand), for: char, type: type)
            count += 1
            if count >= 10 {
                self.handshakeTimer?.invalidate()
                self.startPolling()
            }
        }
    }

    private func startPolling() {
        let pollCommand: [UInt8] = [0x02, 0x01, 0x04, 0x40, 0x84, 0x03]
        let type = writeChar.flatMap { preferredWriteType(for: $0) } ?? .withResponse
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self = self, let p = self.peripheral, let char = self.writeChar else { return }
            p.writeValue(Data(pollCommand), for: char, type: type)
        }
    }

    private func updateFrequency() -> Double {
        let now = Date()
        lastPacketTimes.append(now)
        if lastPacketTimes.count > frequencyWindowSize {
            lastPacketTimes.removeFirst()
        }

        guard lastPacketTimes.count >= 2 else { return 0.0 }

        let duration = now.timeIntervalSince(lastPacketTimes.first!)
        return Double(lastPacketTimes.count - 1) / duration
    }
}

extension ESCBleManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if status == .disconnected { scan() }
        case .unauthorized:
            status = .unauthorized
        case .poweredOff:
            status = .poweredOff
        default:
            status = .disconnected
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        if name == targetDeviceName {
            self.peripheral = peripheral
            self.deviceName = name
            self.status = .connecting
            centralManager.stopScan()
            centralManager.connect(peripheral, options: nil)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = .discovering
        peripheral.delegate = self
        peripheral.discoverServices([targetService])
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        status = .disconnected
        telemetry = nil
        cancelTimers()
        scan() // Re-scan
    }

    /// Recover from a connection attempt that failed mid-handshake. Without
    /// this delegate, `status` would stay `.connecting` forever and
    /// `start()` would refuse to re-scan because of the `status == .disconnected`
    /// guard. Mirror the disconnect path: clear state, then re-scan.
    public func centralManager(_ central: CBCentralManager,
                               didFailToConnect peripheral: CBPeripheral,
                               error: Error?) {
        self.peripheral = nil
        self.writeChar = nil
        self.notifyChar = nil
        cancelTimers()
        status = .disconnected
        scan()
    }
}

extension ESCBleManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == targetService {
            peripheral.discoverCharacteristics([targetWrite, targetNotify], for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            if char.uuid == targetWrite {
                writeChar = char
            } else if char.uuid == targetNotify {
                notifyChar = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == targetNotify && characteristic.isNotifying {
            status = .connected
            startHandshake()
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == targetNotify, let data = characteristic.value else { return }

        if let packet = ESCTelemetryPacket(data) {
            messageCount += 1
            let freq = updateFrequency()

            // Apply filtering and conversion
            let filteredRpm = rpmFilter.update(Double(packet.rpm))
            let speedMps = MotorSpeedConverter.rpmToMps(filteredRpm)

            DispatchQueue.main.async {
                self.telemetry = ESCTelemetry(
                    rpm: Int(filteredRpm),
                    speedMps: speedMps,
                    escTemperature: packet.escTemperatureC,
                    motorTemperature: packet.motorTemperatureC,
                    voltage: packet.voltageV,
                    updateFrequency: freq,
                    messageCount: self.messageCount,
                    timestamp: Date()
                )
            }
        }
    }
}

// Telemetry packet decoding lives in ESCTelemetryPacket.swift; CRC-16
// XMODEM lives in Crc16Xmodem.swift. Both are unit-tested.
