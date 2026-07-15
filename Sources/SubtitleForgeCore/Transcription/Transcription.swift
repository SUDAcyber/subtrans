import Foundation

public enum TranscriptionEngine: String, CaseIterable, Codable, Identifiable, Sendable {
    case whisperKit
    case scribe
    case typhoon

    public var id: String { rawValue }
}

/// A recognized span of speech with absolute timestamps in seconds.
public struct TranscribedSegment: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// A single word (or spacing/audio-event token) with timestamps, as returned by
/// word-level engines such as ElevenLabs Scribe.
public struct TranscribedWord: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case word
        case spacing
        case audioEvent
    }

    public var text: String
    public var start: Double
    public var end: Double
    public var kind: Kind

    public init(text: String, start: Double, end: Double, kind: Kind) {
        self.text = text
        self.start = start
        self.end = end
        self.kind = kind
    }
}

public enum TranscriptionProgressUpdate: Sendable {
    case preparingModel
    case downloadingModel(fraction: Double)
    case uploading
    case transcribing(fraction: Double)
}

public protocol SubtitleTranscriber: Sendable {
    /// Transcribes the audio file into timed segments.
    /// - Parameter languageHint: ISO-639-1 code (e.g. "th"), or nil for auto-detect.
    func transcribe(
        audioURL: URL,
        languageHint: String?,
        onProgress: @escaping @Sendable (TranscriptionProgressUpdate) -> Void
    ) async throws -> [TranscribedSegment]
}

public enum SegmentCueBuilder {
    /// Converts recognized segments into SRT-ready subtitle cues.
    public static func makeCues(from segments: [TranscribedSegment]) -> [SubtitleCue] {
        let cleaned = segments
            .map { TranscribedSegment(start: $0.start, end: max($0.end, $0.start + 0.3), text: normalize($0.text)) }
            .filter { !$0.text.isEmpty }
            .sorted { $0.start < $1.start }

        return cleaned.enumerated().map { index, segment in
            var end = segment.end
            // Keep cues from overlapping the next line.
            if index + 1 < cleaned.count {
                end = min(end, cleaned[index + 1].start)
                end = max(end, segment.start + 0.3)
            }
            return SubtitleCue(
                sequence: index + 1,
                startTime: timecode(segment.start),
                endTime: timecode(end),
                text: segment.text
            )
        }
    }

    /// Groups word-level timestamps into subtitle-sized segments. Splits on speech
    /// gaps, then on duration/length budgets so lines stay readable.
    public static func makeSegments(
        from words: [TranscribedWord],
        maxDuration: Double = 5.5,
        maxCharacters: Int = 54,
        gapThreshold: Double = 0.7
    ) -> [TranscribedSegment] {
        var segments: [TranscribedSegment] = []
        var text = ""
        var start: Double?
        var end: Double = 0

        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let start, !trimmed.isEmpty {
                segments.append(TranscribedSegment(start: start, end: end, text: trimmed))
            }
            text = ""
            start = nil
        }

        for word in words {
            switch word.kind {
            case .audioEvent:
                continue
            case .spacing:
                if start != nil { text += " " }
                continue
            case .word:
                break
            }

            if let currentStart = start {
                let gap = word.start - end
                let wouldExceedDuration = word.end - currentStart > maxDuration
                let wouldExceedLength = text.count + word.text.count > maxCharacters
                if gap > gapThreshold || wouldExceedDuration || wouldExceedLength {
                    flush()
                }
            }

            if start == nil {
                start = word.start
            }
            text += word.text
            end = word.end
        }
        flush()

        return segments
    }

    public static func timecode(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let totalMilliseconds = Int((clamped * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = totalMilliseconds / 60_000 % 60
        let secs = totalMilliseconds / 1000 % 60
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, milliseconds)
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
