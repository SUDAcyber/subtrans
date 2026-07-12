import Foundation

public enum ScribeTranscriberError: Error, LocalizedError {
    case emptyAPIKey
    case unreadableAudio
    case httpError(statusCode: Int, message: String)
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "请先在识别设置中填写 ElevenLabs 密钥"
        case .unreadableAudio:
            return "无法读取音频文件"
        case let .httpError(statusCode, message):
            return "识别请求失败 \(statusCode)：\(message)"
        case .emptyResult:
            return "识别结果为空"
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
        guard let audioData = try? Data(contentsOf: audioURL) else {
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
        if let languageHint, !languageHint.isEmpty, languageHint != "auto" {
            fields.append(("language_code", languageHint))
        }

        var body = Data()
        for field in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
            body.append("\(field.value)\r\n")
        }
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)
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

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
