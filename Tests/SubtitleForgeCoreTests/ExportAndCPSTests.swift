import XCTest
@testable import SubtitleForgeCore

// Mirrors ValidationReport.cpsThreshold in the app target (not visible from Core tests).
private let ValidationReport_cpsThresholdForTest: Double = 20

final class ExportAndCPSTests: XCTestCase {
    private func cue(_ sequence: Int, start: String, end: String, text: String, translation: String? = nil) -> SubtitleCue {
        SubtitleCue(sequence: sequence, startTime: start, endTime: end, text: text, translation: translation)
    }

    func testDurationCachedThroughCodableRoundTrip() throws {
        let original = cue(1, start: "00:00:01,000", end: "00:00:03,500", text: "hi", translation: "你好")
        XCTAssertEqual(original.durationSeconds, 2.5)
        // Old history JSON never stored durationSeconds; a decode must recompute it.
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SubtitleCue.self, from: data)
        XCTAssertEqual(decoded.durationSeconds, 2.5)
        XCTAssertEqual(decoded.translation, "你好")

        // A cue decoded from JSON that lacks the durationSeconds key still works.
        let legacyJSON = #"{"sequence":2,"startTime":"00:00:00,000","endTime":"00:00:02,000","text":"x","translation":"甲乙"}"#
        let legacy = try JSONDecoder().decode(SubtitleCue.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(legacy.durationSeconds, 2.0)
        XCTAssertEqual(legacy.translationCPS ?? 0, 1.0, accuracy: 0.01)
    }

    func testDurationAndCPS() {
        let fast = cue(1, start: "00:00:01,000", end: "00:00:02,000", text: "src", translation: "这是一条二十多个字符长度明显超标的译文内容")
        XCTAssertEqual(fast.durationSeconds, 1.0)
        XCTAssertEqual(fast.translationCPS ?? 0, 21, accuracy: 0.01)
        XCTAssertGreaterThan(fast.translationCPS ?? 0, ValidationReport_cpsThresholdForTest)

        let slow = cue(2, start: "00:00:01,000", end: "00:00:05,000", text: "src", translation: "四个字符")
        XCTAssertEqual(slow.translationCPS ?? 0, 1.0, accuracy: 0.01)

        let untranslated = cue(3, start: "00:00:01,000", end: "00:00:02,000", text: "src")
        XCTAssertNil(untranslated.translationCPS)

        let badTimecode = cue(4, start: "abc", end: "def", text: "src", translation: "x")
        XCTAssertNil(badTimecode.durationSeconds)
    }

    func testBilingualExportLayouts() {
        let cues = [
            cue(1, start: "00:00:01,000", end: "00:00:02,000", text: "hello", translation: "你好"),
            cue(2, start: "00:00:03,000", end: "00:00:04,000", text: "world")
        ]

        let translationFirst = SRTParser.render(cues, layout: .bilingualTranslationFirst)
        XCTAssertTrue(translationFirst.contains("你好\nhello"))
        XCTAssertTrue(translationFirst.contains("world"))
        XCTAssertFalse(translationFirst.contains("world\nworld"))

        let sourceFirst = SRTParser.render(cues, layout: .bilingualSourceFirst)
        XCTAssertTrue(sourceFirst.contains("hello\n你好"))

        let translationOnly = SRTParser.render(cues, layout: .translationOnly)
        XCTAssertTrue(translationOnly.contains("你好"))
        XCTAssertFalse(translationOnly.contains("hello"))

        // Round-trip: bilingual output must still parse as valid SRT.
        XCTAssertNoThrow(try SRTParser.parse(translationFirst))
    }

    func testBilingualCollapsesInternalNewlinesToTwoLines() throws {
        let cues = [
            SubtitleCue(sequence: 1, startTime: "00:00:01,000", endTime: "00:00:02,000",
                        text: "line one\nline two", translation: "译文甲\n译文乙")
        ]
        let rendered = SRTParser.render(cues, layout: .bilingualTranslationFirst)
        // A cue block = index, timecode, then exactly two text lines.
        let block = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 4) // seq, timecode, translation line, source line
        XCTAssertEqual(lines[2], "译文甲 译文乙")
        XCTAssertEqual(lines[3], "line one line two")
    }
}
