import XCTest
@testable import SubtitleForgeCore

final class SegmentCueBuilderTests: XCTestCase {
    func testMakesCuesWithSRTTimecodesAndSequences() {
        let segments = [
            TranscribedSegment(start: 0.0, end: 2.5, text: "  hello   world "),
            TranscribedSegment(start: 3.0, end: 5.75, text: "line two"),
            TranscribedSegment(start: 6.0, end: 6.0, text: "   ")
        ]

        let cues = SegmentCueBuilder.makeCues(from: segments)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].sequence, 1)
        XCTAssertEqual(cues[0].startTime, "00:00:00,000")
        XCTAssertEqual(cues[0].endTime, "00:00:02,500")
        XCTAssertEqual(cues[0].text, "hello world")
        XCTAssertEqual(cues[1].sequence, 2)
        XCTAssertEqual(cues[1].endTime, "00:00:05,750")
    }

    func testCuesDoNotOverlapNextSegment() {
        let segments = [
            TranscribedSegment(start: 0.0, end: 4.0, text: "a"),
            TranscribedSegment(start: 2.0, end: 5.0, text: "b")
        ]
        let cues = SegmentCueBuilder.makeCues(from: segments)
        XCTAssertEqual(cues[0].endTime, "00:00:02,000")
    }

    func testTimecodeFormatsHoursAndMilliseconds() {
        XCTAssertEqual(SegmentCueBuilder.timecode(3661.042), "01:01:01,042")
        XCTAssertEqual(SegmentCueBuilder.timecode(-5), "00:00:00,000")
    }

    func testGroupsWordsOnGapsAndBudgets() {
        var words: [TranscribedWord] = []
        // First phrase: 0.0-1.0s, second phrase after a 1.5s gap.
        words.append(TranscribedWord(text: "สวัสดี", start: 0.0, end: 0.5, kind: .word))
        words.append(TranscribedWord(text: "ครับ", start: 0.5, end: 1.0, kind: .word))
        words.append(TranscribedWord(text: "ไปไหน", start: 2.5, end: 3.0, kind: .word))
        words.append(TranscribedWord(text: "(music)", start: 3.0, end: 4.0, kind: .audioEvent))

        let segments = SegmentCueBuilder.makeSegments(from: words)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "สวัสดีครับ")
        XCTAssertEqual(segments[0].start, 0.0)
        XCTAssertEqual(segments[0].end, 1.0)
        XCTAssertEqual(segments[1].text, "ไปไหน")
    }

    func testSplitsLongSegmentsByDuration() {
        let words = (0..<20).map { index in
            TranscribedWord(text: "w\(index)", start: Double(index), end: Double(index) + 0.6, kind: .word)
        }
        let segments = SegmentCueBuilder.makeSegments(from: words, maxDuration: 5.0, maxCharacters: 500, gapThreshold: 0.7)
        XCTAssertGreaterThan(segments.count, 1)
        for segment in segments {
            XCTAssertLessThanOrEqual(segment.end - segment.start, 6.0)
        }
    }
}
