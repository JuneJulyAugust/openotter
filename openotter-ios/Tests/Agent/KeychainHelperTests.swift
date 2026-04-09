import XCTest
@testable import openotter

final class KeychainHelperTests: XCTestCase {

    private let testService = "com.openotter.test.keychain"
    private let testKey = "test-token"

    override func tearDown() {
        super.tearDown()
        KeychainHelper.delete(key: testKey, service: testService)
    }

    func testSaveAndRead() {
        let saved = KeychainHelper.save(key: testKey, value: "abc123", service: testService)
        XCTAssertTrue(saved)
        let read = KeychainHelper.read(key: testKey, service: testService)
        XCTAssertEqual(read, "abc123")
    }

    func testReadMissingKeyReturnsNil() {
        let read = KeychainHelper.read(key: "nonexistent", service: testService)
        XCTAssertNil(read)
    }

    func testOverwriteExistingValue() {
        KeychainHelper.save(key: testKey, value: "old", service: testService)
        KeychainHelper.save(key: testKey, value: "new", service: testService)
        let read = KeychainHelper.read(key: testKey, service: testService)
        XCTAssertEqual(read, "new")
    }

    func testDeleteRemovesValue() {
        KeychainHelper.save(key: testKey, value: "toDelete", service: testService)
        KeychainHelper.delete(key: testKey, service: testService)
        let read = KeychainHelper.read(key: testKey, service: testService)
        XCTAssertNil(read)
    }
}
