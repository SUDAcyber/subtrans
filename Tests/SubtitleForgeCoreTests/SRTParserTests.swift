import XCTest
@testable import SubtitleForgeCore

final class SRTParserTests: XCTestCase {
    func testParseMultilineCueAndRenderTranslation() throws {
        let input = """
        1
        00:00:01,000 --> 00:00:04,000
        Hello
        world

        2
        00:00:05,000 --> 00:00:08,000
        Uh, this is fine.

        """

        var cues = try SRTParser.parse(input)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].sequence, 1)
        XCTAssertEqual(cues[0].timecode, "00:00:01,000 --> 00:00:04,000")
        XCTAssertEqual(cues[0].text, "Hello\nworld")

        cues[0].translation = "你好 世界"
        cues[1].translation = "没问题"

        let output = SRTParser.render(cues)
        XCTAssertTrue(output.contains("00:00:01,000 --> 00:00:04,000\n你好 世界"))
        XCTAssertTrue(output.contains("2\n00:00:05,000 --> 00:00:08,000\n没问题"))
    }

    func testThrowsForMalformedSequence() {
        XCTAssertThrowsError(try SRTParser.parse("one\n00:00:01,000 --> 00:00:02,000\nHello\n")) { error in
            XCTAssertEqual(error as? SRTParserError, .malformedSequence(line: 1, value: "one"))
        }
    }
}
