import Foundation

public struct SubtitleCue: Codable, Hashable, Identifiable, Sendable {
    public var id: Int { sequence }

    public let sequence: Int
    public let startTime: String
    public let endTime: String
    public let text: String
    public var translation: String?

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
    }

    public var timecode: String {
        "\(startTime) --> \(endTime)"
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
