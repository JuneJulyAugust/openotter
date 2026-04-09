import Foundation
import CoreBluetooth
import Combine

public enum ESCBleStatus: String {
    case disconnected = "Disconnected"
    case scanning = "Scanning"
    case connecting = "Connecting"
    case discovering = "Discovering"
    case connected = "Connected"
    case unauthorized = "Unauthorized"
    case poweredOff = "Bluetooth Off"
}

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
        
        if let packet = TelemetryPacket(data) {
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

// Internal packet parsing logic ported from esc_app.swift
private struct TelemetryPacket {
    let escTemperatureC: Double
    let motorTemperatureC: Double
    let voltageV: Double
    let rpm: Int

    init?(_ data: Data, poleCount: Int = 4) {
        let bytes = [UInt8](data)
        guard bytes.count == 79 else { return nil }
        guard bytes[0] == 0x02, bytes[1] == 0x4A, bytes[2] == 0x04, bytes[3] == 0x01 else { return nil }

        let payload = Array(bytes[2..<(bytes.count - 3)])
        let expectedChecksum = (UInt16(bytes[bytes.count - 3]) << 8) | UInt16(bytes[bytes.count - 2])
        guard Self.crc16Xmodem(payload) == expectedChecksum else { return nil }

        escTemperatureC = Double(Self.signed16BE(bytes[3], bytes[4])) / 10.0
        motorTemperatureC = Double(Self.signed16BE(bytes[5], bytes[6])) / 10.0
        
        let erpmRaw = Self.signed32BE(bytes[25], bytes[26], bytes[27], bytes[28])
        rpm = Int((Double(erpmRaw) * 2.0) / Double(poleCount))
        
        let voltageRaw = (UInt16(bytes[29]) << 8) | UInt16(bytes[30])
        voltageV = Double(voltageRaw) / 10.0
    }

    private static func signed16BE(_ high: UInt8, _ low: UInt8) -> Int {
        Int(Int16(bitPattern: (UInt16(high) << 8) | UInt16(low)))
    }

    private static func signed32BE(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> Int {
        let value = (UInt32(b0) << 24) | (UInt32(b1) << 16) | (UInt32(b2) << 8) | UInt32(b3)
        return Int(Int32(bitPattern: value))
    }

    private static func crc16Xmodem(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc &<< 1) ^ 0x1021
                } else {
                    crc = crc &<< 1
                }
            }
        }
        return crc
    }
}
