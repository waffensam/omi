import XCTest
@testable import Omi_Computer

final class NotificationTextSanitizerTests: XCTestCase {
    func testSanitizeRepairsGB18030EmojiMojibakeInsideChineseText() {
        let input = "提醒：馃槉 明天 10 点开会"

        XCTAssertEqual(
            NotificationTextSanitizer.sanitize(input),
            "提醒：😊 明天 10 点开会"
        )
    }

    func testSanitizeRepairsWindows1252EmojiMojibake() {
        let input = "Reminder: deploy ðŸ”¥ today"

        XCTAssertEqual(
            NotificationTextSanitizer.sanitize(input),
            "Reminder: deploy 🔥 today"
        )
    }

    func testSanitizeRepairsWindows1252SymbolEmojiSequences() {
        let input = "Status âœ… all green"

        XCTAssertEqual(
            NotificationTextSanitizer.sanitize(input),
            "Status ✅ all green"
        )
    }

    func testSanitizeLeavesNormalChineseAndEmojiUntouched() {
        let input = "提醒：😊 明天 10 点开会"

        XCTAssertEqual(NotificationTextSanitizer.sanitize(input), input)
    }
}
