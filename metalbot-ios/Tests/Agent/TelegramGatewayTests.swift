import XCTest
@testable import metalbot

final class TelegramGatewayTests: XCTestCase {

    func testParseValidUpdate() throws {
        let json = """
        {
            "ok": true,
            "result": [{
                "update_id": 100,
                "message": {
                    "message_id": 1,
                    "from": {"id": 456, "first_name": "Fang", "username": "fangxu"},
                    "chat": {"id": 789},
                    "date": 1712300000,
                    "text": "/forward"
                }
            }]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TelegramUpdateResponse.self, from: json)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.result.count, 1)

        let update = response.result[0]
        XCTAssertEqual(update.updateId, 100)
        XCTAssertEqual(update.message?.text, "/forward")
        XCTAssertEqual(update.message?.chat.id, 789)
        XCTAssertEqual(update.message?.from?.username, "fangxu")
    }

    func testParseEmptyResult() throws {
        let json = """
        {"ok": true, "result": []}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TelegramUpdateResponse.self, from: json)
        XCTAssertTrue(response.ok)
        XCTAssertTrue(response.result.isEmpty)
    }

    func testParseUpdateWithoutMessage() throws {
        let json = """
        {"ok": true, "result": [{"update_id": 101}]}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TelegramUpdateResponse.self, from: json)
        XCTAssertEqual(response.result.count, 1)
        XCTAssertNil(response.result[0].message)
    }

    func testTelegramMessageConversion() {
        let chatMsg = TelegramChat(id: 789)
        let fromUser = TelegramUser(id: 456, firstName: "Fang", username: "fangxu")
        let apiMsg = TelegramAPIMessage(
            messageId: 1,
            from: fromUser,
            chat: chatMsg,
            date: 1712300000,
            text: "/forward"
        )

        let msg = TelegramMessage(from: apiMsg)
        XCTAssertEqual(msg.chatId, 789)
        XCTAssertEqual(msg.text, "/forward")
        XCTAssertEqual(msg.fromUsername, "fangxu")
    }

    func testChatIdWhitelistFiltering() {
        let gateway = TelegramGateway(token: "fake")
        gateway.allowedChatIds = [789]

        XCTAssertTrue(gateway.isChatAllowed(789))
        XCTAssertFalse(gateway.isChatAllowed(999))
    }

    func testEmptyWhitelistAllowsNobody() {
        let gateway = TelegramGateway(token: "fake")
        gateway.allowedChatIds = []

        XCTAssertFalse(gateway.isChatAllowed(789))
    }
}
