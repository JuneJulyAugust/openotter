import CoreBluetooth
import Foundation

private struct Options {
    var seconds: TimeInterval = 20
    var duplicateInterval: TimeInterval = 1
    var nameFilter = "OPENOTTER-MCP"
}

private func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--seconds":
            index += 1
            if index < arguments.count, let value = TimeInterval(arguments[index]) {
                options.seconds = value
            }
        case "--name":
            index += 1
            if index < arguments.count {
                options.nameFilter = arguments[index]
            }
        case "--duplicate-interval":
            index += 1
            if index < arguments.count, let value = TimeInterval(arguments[index]) {
                options.duplicateInterval = value
            }
        case "--help", "-h":
            print("""
            Usage: swift firmware/stm32-mcp/scripts/scan_stm32_ble.swift [options]

            Options:
              --seconds N              Scan duration, default 20.
              --name NAME              Highlight matching local/peripheral names, default OPENOTTER-MCP.
              --duplicate-interval N   Minimum seconds between prints for the same peripheral, default 1.
            """)
            exit(0)
        default:
            break
        }
        index += 1
    }
    return options
}

private final class Scanner: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager!
    private var seen: [UUID: Date] = [:]
    private let options: Options
    private let stopAt: Date

    init(options: Options) {
        self.options = options
        self.stopAt = Date().addingTimeInterval(options.seconds)
        super.init()
        self.central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("central state \(central.state.rawValue)")
        guard central.state == .poweredOn else {
            return
        }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let now = Date()
        if now >= stopAt {
            central.stopScan()
            CFRunLoopStop(CFRunLoopGetMain())
            return
        }

        let last = seen[peripheral.identifier] ?? .distantPast
        guard now.timeIntervalSince(last) >= options.duplicateInterval else {
            return
        }
        seen[peripheral.identifier] = now

        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "-"
        let peripheralName = peripheral.name ?? "-"
        let serviceUUIDs = uuidList(advertisementData[CBAdvertisementDataServiceUUIDsKey])
        let overflowUUIDs = uuidList(advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey])
        let solicitedUUIDs = uuidList(advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey])
        let manufacturerHex = hex(advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)
        let match = peripheralName.contains(options.nameFilter) || localName.contains(options.nameFilter)
        let marker = match ? "*" : " "

        print(
            "\(marker) adv id=\(peripheral.identifier.uuidString.prefix(8)) " +
            "name=\(peripheralName) local=\(localName) rssi=\(RSSI) " +
            "svc=\(serviceUUIDs) overflow=\(overflowUUIDs) " +
            "solicited=\(solicitedUUIDs) mfg=\(manufacturerHex)"
        )
    }

    private func uuidList(_ value: Any?) -> String {
        let uuids = (value as? [CBUUID] ?? []).map { $0.uuidString }
        return uuids.isEmpty ? "-" : uuids.joined(separator: ",")
    }

    private func hex(_ data: Data?) -> String {
        guard let data else {
            return "-"
        }
        return data.map { String(format: "%02X", $0) }.joined()
    }
}

private let options = parseOptions(Array(CommandLine.arguments.dropFirst()))
private let scanner = Scanner(options: options)
RunLoop.main.run(until: Date().addingTimeInterval(options.seconds + 2))
_ = scanner
