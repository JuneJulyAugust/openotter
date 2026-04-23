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

/// Operating mode for the firmware (0xFE44 characteristic).
public enum FirmwareMode: UInt8 {
    case drive = 0x00
    case debug = 0x01
}

/// Manages CoreBluetooth connection to the STM32 OPENOTTER-MCP BLE peripheral.
/// Sends 6-byte steering + throttle + velocity commands and subscribes to
/// the 0xFE43 safety characteristic for firmware emergency-brake events.
public class STM32BleManager: NSObject, ObservableObject {

    /// Shared singleton — only one connection to OPENOTTER-MCP may exist at a time.
    public static let shared = STM32BleManager()

    // MARK: - Published State

    @Published public var status: STM32BleStatus = .disconnected
    @Published public var deviceName: String = "Unknown"
    @Published public var rssi: Int = 0
    @Published public var commandsSent: Int = 0
    /// Most recent safety event from firmware 0xFE43. `nil` until first notification.
    @Published public var safetyEvent: FirmwareSafetyEvent?

    // MARK: - BLE UUIDs (must match firmware ble_app.h)

    /// Custom service: 0xFE40
    private let controlServiceUUID = CBUUID(string: "FE40")
    /// Write characteristic: 0xFE41 — receives [int16_t steering, int16_t throttle, int16_t velocity_mm_s]
    private let commandCharUUID = CBUUID(string: "FE41")
    /// Notify characteristic: 0xFE42 — heartbeat/status from firmware
    private let statusCharUUID = CBUUID(string: "FE42")
    /// Notify + Read: 0xFE43 — 20 B safety event (FirmwareSafetyEvent)
    private let safetyCharUUID = CBUUID(string: "FE43")
    /// Write + Read: 0xFE44 — 1 B operating mode (FirmwareMode raw value)
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

    private let targetDeviceName = "OPENOTTER-MCP"

    // MARK: - Init

    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    public func start() {
        guard status == .disconnected else { return }  // already running
        guard centralManager.state == .poweredOn else { return }
        scan()
    }

    public func stop() {
        centralManager.stopScan()
        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanup()
    }

    /// Send steering and throttle pulse widths (in µs) and the current
    /// ground-speed estimate to the STM32.
    ///
    /// - Parameters:
    ///   - steeringMicros: Pulse width in µs [1000, 2000]; 1500 = center.
    ///   - throttleMicros: Pulse width in µs [1000, 2000]; 1500 = neutral.
    ///   - velocityMps:    Signed speed in m/s. Negative = reversing.
    ///                     Clamped to Int16 range (±32 m/s) before send.
    public func sendCommand(steeringMicros: Int16,
                             throttleMicros: Int16,
                             velocityMps: Float = 0.0) {
        guard let commandChar, let peripheral else { return }

        // Convert to Int16 mm/s, clamping to Int16 bounds.
        let velocityMmS = Int16(
            max(Float(Int16.min), min(Float(Int16.max), velocityMps * 1000.0))
        )

        var payload = Data(count: 6)
        payload.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: steeringMicros.littleEndian, toByteOffset: 0, as: Int16.self)
            ptr.storeBytes(of: throttleMicros.littleEndian, toByteOffset: 2, as: Int16.self)
            ptr.storeBytes(of: velocityMmS.littleEndian,    toByteOffset: 4, as: Int16.self)
        }

        let writeType: CBCharacteristicWriteType =
            commandChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(payload, for: commandChar, type: writeType)

        DispatchQueue.main.async {
            self.commandsSent += 1
        }
    }

    /// Write the operating mode to 0xFE44.
    public func writeMode(_ mode: FirmwareMode) {
        guard let modeChar, let peripheral else { return }
        var byte = mode.rawValue
        let data = Data(bytes: &byte, count: 1)
        let writeType: CBCharacteristicWriteType =
            modeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: modeChar, type: writeType)
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
        STM32TofService.shared.detach()
        status = .disconnected
    }

    private func scan() {
        status = .scanning
        /* Scan without service filter — BlueNRG 16-bit UUIDs are often
         * not included in the iOS service-UUID advertisement cache, so
         * a filtered scan silently misses the device.  We match by name
         * in didDiscover instead. */
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
}

// MARK: - CBCentralManagerDelegate

extension STM32BleManager: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if status == .disconnected { scan() }
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
        // After a prior connection iOS caches the GAP device name
        // ("BlueNRG") as peripheral.name, hiding the advertising
        // local name ("OPENOTTER-MCP").  Check both sources.
        let cachedName = peripheral.name ?? ""
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""

        guard cachedName.contains("OPENOTTER") || advName.contains("OPENOTTER") else { return }

        centralManager.stopScan()
        self.peripheral = peripheral
        self.deviceName = advName.isEmpty ? cachedName : advName
        self.rssi = RSSI.intValue
        status = .connecting
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager,
                               didConnect peripheral: CBPeripheral) {
        status = .discovering
        // Discover all services — BlueNRG 16-bit UUIDs may not match
        // the iOS CBUUID filter after reconnection
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        cleanup()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.scan()
        }
    }

    public func centralManager(_ central: CBCentralManager,
                               didFailToConnect peripheral: CBPeripheral,
                               error: Error?) {
        cleanup()
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
        for service in services {
            switch service.uuid {
            case controlServiceUUID:
                peripheral.discoverCharacteristics(
                    [commandCharUUID, statusCharUUID, safetyCharUUID, modeCharUUID],
                    for: service)
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
        guard let chars = service.characteristics else { return }

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
                    /* Read the seeded SAFE value immediately after subscribe. */
                    peripheral.readValue(for: char)
                case modeCharUUID:
                    modeChar = char
                    /* Write Drive (0x00) on every connect so a stale Debug
                     * mode left over from a previous session is cleared. */
                    writeMode(.drive)
                default:
                    break
                }
            }
            if commandChar != nil {
                status = .connected
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
            }

        default:
            break
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        switch characteristic.uuid {
        case tofFrameCharUUID:
            if let data = characteristic.value {
                STM32TofService.shared.handleFrameNotification(data)
            }
        case tofStatusCharUUID:
            if let data = characteristic.value {
                STM32TofService.shared.handleStatusNotification(data)
            }
        case safetyCharUUID:
            if let data = characteristic.value,
               let event = FirmwareSafetyEvent.parse(from: data) {
                DispatchQueue.main.async {
                    self.safetyEvent = event
                }
            }
        case statusCharUUID:
            // FE42 control-side status — no consumer yet.
            break
        default:
            break
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didReadRSSI RSSI: NSNumber,
                           error: Error?) {
        rssi = RSSI.intValue
    }
}
