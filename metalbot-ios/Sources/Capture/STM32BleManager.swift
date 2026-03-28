import Foundation
import CoreBluetooth
import Combine

public enum STM32BleStatus: String {
    case disconnected = "Disconnected"
    case scanning = "Scanning"
    case connecting = "Connecting"
    case discovering = "Discovering"
    case connected = "Connected"
    case unauthorized = "Unauthorized"
    case poweredOff = "Bluetooth Off"
}

/// Manages CoreBluetooth connection to the STM32 METALBOT-MCP BLE peripheral.
/// Sends steering + throttle commands as packed int16_t pairs (4 bytes).
public class STM32BleManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published public var status: STM32BleStatus = .disconnected
    @Published public var deviceName: String = "Unknown"
    @Published public var rssi: Int = 0
    @Published public var commandsSent: Int = 0

    // MARK: - BLE UUIDs (must match firmware ble_app.h)

    /// Custom service: 0xFE40
    private let controlServiceUUID = CBUUID(string: "FE40")
    /// Write characteristic: 0xFE41 — receives [int16_t steering, int16_t throttle]
    private let commandCharUUID = CBUUID(string: "FE41")
    /// Notify characteristic: 0xFE42 — heartbeat/status from firmware
    private let statusCharUUID = CBUUID(string: "FE42")

    // MARK: - Private

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?

    private let targetDeviceName = "METALBOT-MCP"

    // MARK: - Init

    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    public func start() {
        guard centralManager.state == .poweredOn else { return }
        scan()
    }

    public func stop() {
        centralManager.stopScan()
        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        status = .disconnected
    }

    /// Send steering and throttle pulse widths (in µs) to the STM32.
    /// Values are clamped to [1000, 2000] on the firmware side.
    public func sendCommand(steeringMicros: Int16, throttleMicros: Int16) {
        guard let commandChar, let peripheral else { return }

        var payload = Data(count: 4)
        payload.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: steeringMicros.littleEndian, toByteOffset: 0, as: Int16.self)
            ptr.storeBytes(of: throttleMicros.littleEndian, toByteOffset: 2, as: Int16.self)
        }

        let writeType: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(payload, for: commandChar, type: writeType)

        DispatchQueue.main.async {
            self.commandsSent += 1
        }
    }

    // MARK: - Private

    private func scan() {
        status = .scanning
        // Scan for our specific service UUID for faster discovery
        centralManager.scanForPeripherals(withServices: [controlServiceUUID], options: nil)

        // Also scan without filter as fallback (16-bit UUIDs may not appear in advertising)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.status == .scanning else { return }
            self.centralManager.stopScan()
            self.centralManager.scanForPeripherals(withServices: nil, options: nil)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension STM32BleManager: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            scan()
        case .poweredOff:
            status = .poweredOff
        case .unauthorized:
            status = .unauthorized
        default:
            status = .disconnected
        }
    }

    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any],
                               rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""

        guard name.contains("METALBOT") else { return }

        centralManager.stopScan()
        self.peripheral = peripheral
        self.deviceName = name
        self.rssi = RSSI.intValue
        status = .connecting
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager,
                               didConnect peripheral: CBPeripheral) {
        status = .discovering
        peripheral.discoverServices([controlServiceUUID])
    }

    public func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        status = .disconnected
        commandChar = nil
        statusChar = nil
        // Auto-reconnect after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.scan()
        }
    }

    public func centralManager(_ central: CBCentralManager,
                               didFailToConnect peripheral: CBPeripheral,
                               error: Error?) {
        status = .disconnected
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.scan()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension STM32BleManager: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == controlServiceUUID {
            peripheral.discoverCharacteristics([commandCharUUID, statusCharUUID], for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            switch char.uuid {
            case commandCharUUID:
                commandChar = char
            case statusCharUUID:
                statusChar = char
                // Subscribe to status notifications
                if char.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: char)
                }
            default:
                break
            }
        }

        if commandChar != nil {
            status = .connected
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        // Handle status notifications from firmware (future use)
        guard characteristic.uuid == statusCharUUID else { return }
        // Status payload parsing can be extended here
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didReadRSSI RSSI: NSNumber,
                           error: Error?) {
        rssi = RSSI.intValue
    }
}
