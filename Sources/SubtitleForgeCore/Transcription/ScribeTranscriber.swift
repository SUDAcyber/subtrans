import Foundation

public enum ScribeTranscriberError: Error, LocalizedError {
    case emptyAPIKey
    case unreadableAudio
    case httpError(statusCode: Int, message: String)
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "请先在识别设置中填写 ElevenLabs 密钥 / Enter an ElevenLabs API key in Transcribe settings first"
        case .unreadableAudio:
            return "无法读取音频文件 / Could not read the audio file"
        case let .httpError(statusCode, message):
            return "识别请求失败 / Transcription request failed \(statusCode): \(message)"
        case .emptyResult:
            return "识别结果为空 / Transcription returned nothing"
        }
    }
}

/// ElevenLabs Scribe speech-to-text client.
/// https://elevenlabs.io/docs/capabilities/speech-to-text
public final class ScribeTranscriber: SubtitleTranscriber, @unchecked Sendable {
    private let apiKey: String
    private let urlSession: URLSession
    private static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!

    public init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    public func transcribe(
        audioURL: URL,
        languageHint: String?,
        onProgress: @escaping @Sendable (TranscriptionProgressUpdate) -> Void
    ) async throws -> [TranscribedSegment] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ScribeTranscriberError.emptyAPIKey }
        guard FileManager.default.isReadableFile(atPath: audioURL.path) else {
            throw ScribeTranscriberError.unreadableAudio
        }

        onProgress(.uploading)

        let boundary = "SubtitleForge-\(UUID().uuidString)"
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 1800)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var fields: [(name: String, value: String)] = [
            ("model_id", "scribe_v1"),
            ("timestamps_granularity", "word"),
            ("tag_audio_events", "false"),
            ("diarize", "false")
        ]
        if let languageHint {
            fields.append(("language_code", languageHint))
        }

        let multipartURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubtitleForge-Scribe-\(UUID().uuidString).multipart")
        defer { try? FileManager.default.removeItem(at: multipartURL) }
        do {
            try Self.writeMultipartBody(
                to: multipartURL,
                boundary: boundary,
                fields: fields,
                audioURL: audioURL
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ScribeTranscriberError.unreadableAudio
        }
        if let size = try? multipartURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            request.setValue(String(size), forHTTPHeaderField: "Content-Length")
        }

        let (data, response) = try await urlSession.upload(for: request, fromFile: multipartURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "未知错误"
            throw ScribeTranscriberError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        onProgress(.transcribing(fraction: 0.9))

        let decoded = try JSONDecoder().decode(ScribeResponse.self, from: data)
        let words = (decoded.words ?? []).map { word in
            TranscribedWord(
                text: word.text,
                start: word.start ?? 0,
                end: word.end ?? word.start ?? 0,
                kind: word.kind
            )
        }

        let segments = SegmentCueBuilder.makeSegments(from: words)
        if segments.isEmpty {
            let fullText = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fullText.isEmpty else { throw ScribeTranscriberError.emptyResult }
            return [TranscribedSegment(start: 0, end: 5, text: fullText)]
        }
        return segments
    }

    static func writeMultipartBody(
        to outputURL: URL,
        boundary: String,
        fields: [(name: String, value: String)],
        audioURL: URL
    ) throws {
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: outputURL)
        let input = try FileHandle(forReadingFrom: audioURL)
        defer {
            try? output.close()
            try? input.close()
        }

        func write(_ string: String) throws {
            try output.write(contentsOf: Data(string.utf8))
        }

        for field in fields {
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
            try write("\(field.value)\r\n")
        }

        let safeFilename = audioURL.lastPathComponent.replacingOccurrences(of: "\"", with: "_")
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\n")
        try write("Content-Type: application/octet-stream\r\n\r\n")

        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: chunk)
        }
        try write("\r\n--\(boundary)--\r\n")
    }
}

private struct ScribeResponse: Decodable {
    struct Word: Decodable {
        let text: String
        let start: Double?
        let end: Double?
        let type: String?

        var kind: TranscribedWord.Kind {
            switch type {
            case "spacing": return .spacing
            case "audio_event": return .audioEvent
            default: return .word
            }
        }
    }

    let text: String
    let words: [Word]?
}
