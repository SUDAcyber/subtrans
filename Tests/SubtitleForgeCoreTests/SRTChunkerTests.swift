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
}
