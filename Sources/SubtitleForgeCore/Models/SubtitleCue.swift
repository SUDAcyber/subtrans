import Foundation

public struct SubtitleCue: Codable, Hashable, Identifiable, Sendable {
    public var id: Int { sequence }

    public let sequence: Int
    public let startTime: String
    public let endTime: String
    public let text: String
    public var translation: String?
    /// Duration parsed once at construction; SwiftUI re-renders and validation
    /// passes read this instead of re-parsing the timecode strings each time.
    public let durationSeconds: Double?

    public init(
        sequence: Int,
        startTime: String,
        endTime: String,
        text: String,
        translation: String? = nil
    ) {
        self.sequence = sequence
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.translation = translation
        self.durationSeconds = Self.computeDuration(start: startTime, end: endTime)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sequence = try container.decode(Int.self, forKey: .sequence)
        self.startTime = try container.decode(String.self, forKey: .startTime)
        self.endTime = try container.decode(String.self, forKey: .endTime)
        self.text = try container.decode(String.self, forKey: .text)
        self.translation = try container.decodeIfPresent(String.self, forKey: .translation)
        // Recompute rather than persist, so old history JSON upgrades transparently.
        self.durationSeconds = Self.computeDuration(start: startTime, end: endTime)
    }

    private enum CodingKeys: String, CodingKey {
        case sequence, startTime, endTime, text, translation
    }

    private static func computeDuration(start: String, end: String) -> Double? {
        guard let startSeconds = seconds(fromTimecode: start),
              let endSeconds = seconds(fromTimecode: end),
              endSeconds > startSeconds
        else {
            return nil
        }
        return endSeconds - startSeconds
    }

    public var timecode: String {
        "\(startTime) --> \(endTime)"
    }

    /// Characters-per-second reading speed of the translation, nil when there is
    /// no translation or no valid duration.
    public var translationCPS: Double? {
        guard let translation, let duration = durationSeconds, duration > 0 else { return nil }
        // Count visible characters without allocating a stripped copy.
        var length = 0
        for character in translation where !character.isWhitespace {
            length += 1
        }
        guard length > 0 else { return nil }
        return Double(length) / duration
    }

    /// Parses "HH:MM:SS,mmm" (or with '.') into seconds.
    public static func seconds(fromTimecode timecode: String) -> Double? {
        let normalized = timecode.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2])
        else {
            return nil
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    public var hasTranslation: Bool {
        guard let translation else { return false }
        return !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func renderedText(preferTranslation: Bool = true) -> String {
        if preferTranslation, let translation, !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return translation
        }
        return text
    }
}
