import Foundation
import UIKit
import Combine

class RaspberryPiControlViewModel: ObservableObject {
    @Published var connectionStatus: String = "Disconnected"
    @Published var hbSentCount: Int = 0
    @Published var hbReceivedCount: Int = 0
    @Published var cmdSentCount: Int = 0
    @Published var lastSentTime: String = "Never"
    @Published var lastReceivedTime: String = "Never"
    @Published var steering: Float = 0.0
    @Published var motor: Float = 0.0

    @Published var iphoneIP: String = "Unknown"
    @Published var iphoneName: String = UIDevice.current.name

    @Published var escStatus: ESCBleStatus = .disconnected
    @Published var escTelemetry: ESCTelemetry?
    @Published var escDeviceName: String = "Unknown"

    private let connection: MCPConnection
    private let escManager = ESCBleManager.shared
    private var cancellables = Set<AnyCancellable>()

    private let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    init(connection: MCPConnection? = nil) {
        let conn = connection ?? MCPConnection(host: "192.168.2.189", port: 8888)
        self.connection = conn
        iphoneIP = Self.getInterfaceIPAddress() ?? "0.0.0.0"
        setupCallbacks()
        setupEscSubscriptions()
        conn.connect()
        escManager.start()  // idempotent — no-op if already connected
        startHeartbeat()
    }

    deinit {
        connection.disconnect()
        // ESCBleManager.shared is not stopped — it outlives this viewmodel
    }

    // MARK: - Setup

    private func setupEscSubscriptions() {
        escManager.$status
            .receive(on: DispatchQueue.main)
            .assign(to: &$escStatus)

        escManager.$telemetry
            .receive(on: DispatchQueue.main)
            .assign(to: &$escTelemetry)

        escManager.$deviceName
            .receive(on: DispatchQueue.main)
            .assign(to: &$escDeviceName)
    }

    private func setupCallbacks() {
        connection.onMessageReceived = { [weak self] msg in
            guard let self else { return }
            if MCPProtocol.isHeartbeatResponse(msg) {
                self.hbReceivedCount += 1
                self.lastReceivedTime = self.timeFormatter.string(from: Date())
                self.connectionStatus = "Connected"
                self.connection.resetTimeout()
            }
        }

        connection.onConnectionStatusChanged = { [weak self] connected in
            guard let self else { return }
            if !connected {
                self.connectionStatus = "Disconnected (Timeout)"
            }
        }
    }

    // MARK: - Heartbeat

    func startHeartbeat() {
        connection.startHeartbeat(interval: 1.0) { [weak self] in
            guard let self else { return "" }
            let msg = MCPProtocol.formatHeartbeat(seq: self.hbSentCount)
            DispatchQueue.main.async {
                self.hbSentCount += 1
                self.lastSentTime = self.timeFormatter.string(from: Date())
            }
            return msg
        }
    }

    // MARK: - Commands

    func sendCommand() {
        let msg = MCPProtocol.formatCommand(steering: steering, motor: motor)
        connection.send(message: msg)
        DispatchQueue.main.async {
            self.cmdSentCount += 1
        }
    }

    func updateSteering(_ val: Float) {
        steering = val
        sendCommand()
    }

    func updateMotor(_ val: Float) {
        motor = val
        sendCommand()
    }

    // MARK: - Utility

    static func getInterfaceIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                let interface = ptr?.pointee
                let addrFamily = interface?.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: (interface?.ifa_name)!)
                    if name == "en0" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface?.ifa_addr, socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                                    &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }
}
