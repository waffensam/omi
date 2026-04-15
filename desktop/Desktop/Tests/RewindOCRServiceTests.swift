import XCTest
@testable import Omi_Computer

final class RewindOCRServiceTests: XCTestCase {
    func testPreferredRecognitionLanguagesPrioritizesPreferredChineseLocale() {
        let languages = RewindOCRService.preferredRecognitionLanguages(from: ["zh-Hans-CN"])

        XCTAssertEqual(languages.first, "zh-Hans")
        XCTAssertTrue(languages.contains("en-US"))
        XCTAssertTrue(languages.contains("zh-Hant"))
        XCTAssertTrue(languages.contains("ja-JP"))
        XCTAssertTrue(languages.contains("ko-KR"))
    }

    func testPreferredRecognitionLanguagesNormalizesTraditionalChineseLocale() {
        let languages = RewindOCRService.preferredRecognitionLanguages(from: ["zh-Hant-TW"])

        XCTAssertEqual(languages.first, "zh-Hant")
        XCTAssertTrue(languages.contains("zh-Hans"))
    }

    func testPreferredRecognitionLanguagesDeduplicatesFallbacks() {
        let languages = RewindOCRService.preferredRecognitionLanguages(from: ["en-US", "en_GB", "ja-JP"])

        XCTAssertEqual(languages.filter { $0 == "en-US" }.count, 1)
        XCTAssertEqual(languages.filter { $0 == "ja-JP" }.count, 1)
    }
}
