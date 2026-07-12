import Foundation
import XCTest
@testable import SubtitleForgeCore

final class ScribeMultipartTests: XCTestCase {
    func testMultipartBodyStreamsAudioBytesIntoTemporaryFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScribeMultipartTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioURL = directory.appendingPathComponent("sample.wav")
        let outputURL = directory.appendingPathComponent("body.multipart")
        let audio = Data(repeating: 0xA5, count: 2_500_000)
        try audio.write(to: audioURL)

        try ScribeTranscriber.writeMultipartBody(
            to: outputURL,
            boundary: "test-boundary",
            fields: [("model_id", "scribe_v1")],
            audioURL: audioURL
        )

        let body = try Data(contentsOf: outputURL)
        XCTAssertGreaterThan(body.count, audio.count)
        XCTAssertTrue(body.starts(with: Data("--test-boundary\r\n".utf8)))
        XCTAssertNotNil(body.range(of: audio))
        let footer = Data("--test-boundary--\r\n".utf8)
        XCTAssertTrue(body.suffix(footer.count).elementsEqual(footer))
    }
}
