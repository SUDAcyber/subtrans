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

    func testPartialParseAcceptsSubsetAndReportsMissing() throws {
        let output = #"{"translations":[{"id":1,"text":"ok"},{"id":9,"text":"stray"}]}"#
        let result = try TranslationResultParser.parsePartial(output, expectedIDs: [1, 2, 3], stripPunctuation: false)
        XCTAssertEqual(result.translations, [1: "ok"])
        XCTAssertEqual(result.missingIDs, [2, 3])
    }

    func testPartialParseTreatsEmptyTextAsMissing() throws {
        let output = #"{"translations":[{"id":1,"text":"好"},{"id":2,"text":"  "}]}"#
        let result = try TranslationResultParser.parsePartial(output, expectedIDs: [1, 2], stripPunctuation: true)
        XCTAssertEqual(result.translations, [1: "好"])
        XCTAssertEqual(result.missingIDs, [2])
    }
}
