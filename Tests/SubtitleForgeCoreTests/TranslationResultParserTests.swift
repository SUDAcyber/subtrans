import XCTest
@testable import SubtitleForgeCore

final class TranslationResultParserTests: XCTestCase {
    func testParsesFencedJSONAndSanitizesPunctuation() throws {
        let output = """
        ```json
        {"translations":[{"id":1,"text":"你好，世界！"},{"id":2,"text":"没问题。"}]}
        ```
        """

        let translations = try TranslationResultParser.parse(output, expectedIDs: [1, 2], stripPunctuation: true)
        XCTAssertEqual(translations[1], "你好 世界")
        XCTAssertEqual(translations[2], "没问题")
    }

    func testMissingIDFailsValidation() {
        let output = #"{"translations":[{"id":1,"text":"ok"}]}"#
        XCTAssertThrowsError(try TranslationResultParser.parse(output, expectedIDs: [1, 2], stripPunctuation: false)) { error in
            XCTAssertEqual(error as? TranslationResultParserError, .missingIDs([2]))
        }
    }
}
