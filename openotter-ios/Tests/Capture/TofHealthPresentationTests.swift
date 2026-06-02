import XCTest
@testable import openotter

final class TofHealthPresentationTests: XCTestCase {
    func testRunningHealth() {
        let presentation = TofHealthPresentation(state: .running,
                                                 lastError: 0,
                                                 scanHz: 30)

        XCTAssertEqual(presentation.statusText, "RUNNING")
        XCTAssertEqual(presentation.detailText, "30 Hz")
        XCTAssertEqual(presentation.compactDetailText, "30 Hz")
        XCTAssertFalse(presentation.isError)
    }

    func testNoSensorError() {
        let presentation = TofHealthPresentation(state: .error,
                                                 lastError: 1,
                                                 scanHz: 0)

        XCTAssertEqual(presentation.statusText, "ERROR")
        XCTAssertEqual(presentation.detailText, "VL53L8CX not detected")
        XCTAssertEqual(presentation.compactDetailText, "No sensor")
        XCTAssertTrue(presentation.isError)
    }

    func testLockedModeIsNotHealthFailure() {
        let presentation = TofHealthPresentation(state: .running,
                                                 lastError: 11,
                                                 scanHz: 30)

        XCTAssertEqual(presentation.detailText, "Config locked outside Debug mode")
        XCTAssertEqual(presentation.compactDetailText, "Locked")
        XCTAssertFalse(presentation.isError)
    }
}
