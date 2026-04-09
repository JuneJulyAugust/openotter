import XCTest
@testable import openotter

final class MCPProtocolTests: XCTestCase {

    // MARK: - formatHeartbeat

    func testFormatHeartbeatZero() {
        XCTAssertEqual(MCPProtocol.formatHeartbeat(seq: 0), "hb_iphone:0")
    }

    func testFormatHeartbeatPositive() {
        XCTAssertEqual(MCPProtocol.formatHeartbeat(seq: 42), "hb_iphone:42")
    }

    func testFormatHeartbeatLargeNumber() {
        XCTAssertEqual(MCPProtocol.formatHeartbeat(seq: 99999), "hb_iphone:99999")
    }

    // MARK: - formatCommand

    func testFormatCommandPositive() {
        let result = MCPProtocol.formatCommand(steering: 0.50, motor: 0.75)
        XCTAssertEqual(result, "cmd:s=0.50,m=0.75")
    }

    func testFormatCommandNegative() {
        let result = MCPProtocol.formatCommand(steering: -1.00, motor: -0.25)
        XCTAssertEqual(result, "cmd:s=-1.00,m=-0.25")
    }

    func testFormatCommandZero() {
        let result = MCPProtocol.formatCommand(steering: 0, motor: 0)
        XCTAssertEqual(result, "cmd:s=0.00,m=0.00")
    }

    func testFormatCommandBoundaryValues() {
        let result = MCPProtocol.formatCommand(steering: -1.0, motor: 1.0)
        XCTAssertEqual(result, "cmd:s=-1.00,m=1.00")
    }

    // MARK: - isHeartbeatResponse

    func testIsHeartbeatResponseValid() {
        XCTAssertTrue(MCPProtocol.isHeartbeatResponse("hb_pi:0"))
        XCTAssertTrue(MCPProtocol.isHeartbeatResponse("hb_pi:42"))
        XCTAssertTrue(MCPProtocol.isHeartbeatResponse("hb_pi:123456"))
    }

    func testIsHeartbeatResponseRejectsCommand() {
        XCTAssertFalse(MCPProtocol.isHeartbeatResponse("cmd:s=0.00,m=0.00"))
    }

    func testIsHeartbeatResponseRejectsIPhoneHeartbeat() {
        XCTAssertFalse(MCPProtocol.isHeartbeatResponse("hb_iphone:5"))
    }

    func testIsHeartbeatResponseRejectsEmpty() {
        XCTAssertFalse(MCPProtocol.isHeartbeatResponse(""))
    }

    func testIsHeartbeatResponseRejectsGarbage() {
        XCTAssertFalse(MCPProtocol.isHeartbeatResponse("hello"))
    }

    // MARK: - Round-trip consistency
    // Verify that iOS-formatted messages match what MCP C++ side expects.

    func testHeartbeatFormatMatchesMCPExpectation() {
        // MCP expects messages starting with "hb_iphone:"
        let msg = MCPProtocol.formatHeartbeat(seq: 7)
        XCTAssertTrue(msg.hasPrefix("hb_iphone:"))
    }

    func testCommandFormatMatchesMCPExpectation() {
        // MCP expects "cmd:s=<float>,m=<float>"
        let msg = MCPProtocol.formatCommand(steering: 0.5, motor: -0.3)
        XCTAssertTrue(msg.hasPrefix("cmd:"))
        XCTAssertTrue(msg.contains("s="))
        XCTAssertTrue(msg.contains("m="))
    }
}
