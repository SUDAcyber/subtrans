import XCTest
@testable import SubtitleForgeCore

final class SRTChunkerTests: XCTestCase {
    func testChunksByCueLimitAndAddsContext() {
        let cues = (1...7).map {
            SubtitleCue(sequence: $0, startTime: "00:00:0\($0),000", endTime: "00:00:0\($0),500", text: "line \($0)")
        }

        let batches = SRTChunker.makeBatches(
            cues: cues,
            maxCueCount: 3,
            maxSourceCharacters: 10_000,
            contextOverlap: 1
        )

        XCTAssertEqual(batches.count, 3)
        XCTAssertEqual(batches[0].expectedIDs, [1, 2, 3])
        XCTAssertEqual(batches[1].contextBefore.map(\.sequence), [3])
        XCTAssertEqual(batches[1].expectedIDs, [4, 5, 6])
        XCTAssertEqual(batches[1].contextAfter.map(\.sequence), [7])
        XCTAssertEqual(batches[2].expectedIDs, [7])
    }

    func testSkipTranslatedOnlyBatchesPendingCues() {
        let cues = (1...6).map {
            SubtitleCue(
                sequence: $0,
                startTime: "00:00:0\($0),000",
                endTime: "00:00:0\($0),500",
                text: "line \($0)",
                translation: $0 <= 2 || $0 == 5 ? "译文 \($0)" : nil
            )
        }

        let batches = SRTChunker.makeBatches(
            cues: cues,
            maxCueCount: 10,
            maxSourceCharacters: 10_000,
            contextOverlap: 1,
            skipTranslated: true
        )

        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].expectedIDs, [3, 4, 6])
        XCTAssertEqual(batches[0].contextBefore.map(\.sequence), [2])
    }

    func testSkipTranslatedReturnsEmptyWhenComplete() {
        let cues = (1...3).map {
            SubtitleCue(sequence: $0, startTime: "0", endTime: "1", text: "line", translation: "done")
        }
        let batches = SRTChunker.makeBatches(
            cues: cues,
            maxCueCount: 10,
            maxSourceCharacters: 10_000,
            contextOverlap: 1,
            skipTranslated: true
        )
        XCTAssertTrue(batches.isEmpty)
    }
}
