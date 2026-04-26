import XCTest
@testable import openotter

final class STM32BleModeTransitionTests: XCTestCase {

    func testEnteringDebugWaitsForModeAckBeforeEnablingDebugStreaming() {
        XCTAssertEqual(STM32ModeTransitionPolicy.startActions(for: .debug),
                       [.armDebugStreamingAfterModeWriteAck,
                        .writeMode(.debug)])
    }

    func testLeavingDebugDisablesDebugStreamingBeforeDriveOrParkWrite() {
        XCTAssertEqual(STM32ModeTransitionPolicy.startActions(for: .drive),
                       [.setDebugStreamingEnabled(false),
                        .writeMode(.drive)])
        XCTAssertEqual(STM32ModeTransitionPolicy.startActions(for: .park),
                       [.setDebugStreamingEnabled(false),
                        .writeMode(.park)])
    }

    func testOnlySuccessfulDebugModeAckEnablesDebugStreaming() {
        XCTAssertTrue(STM32ModeTransitionPolicy.shouldEnableDebugStreamingAfterModeAck(
            pendingEnable: true,
            requestedMode: .debug,
            writeSucceeded: true))
        XCTAssertFalse(STM32ModeTransitionPolicy.shouldEnableDebugStreamingAfterModeAck(
            pendingEnable: true,
            requestedMode: .drive,
            writeSucceeded: true))
        XCTAssertFalse(STM32ModeTransitionPolicy.shouldEnableDebugStreamingAfterModeAck(
            pendingEnable: true,
            requestedMode: .debug,
            writeSucceeded: false))
        XCTAssertFalse(STM32ModeTransitionPolicy.shouldEnableDebugStreamingAfterModeAck(
            pendingEnable: false,
            requestedMode: .debug,
            writeSucceeded: true))
    }
}
