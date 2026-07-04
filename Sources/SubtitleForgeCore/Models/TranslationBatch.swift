import Foundation

public struct TranslationBatch: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let batchNumber: Int
    public let totalBatches: Int
    public let focusedCues: [SubtitleCue]
    public let contextBefore: [SubtitleCue]
    public let contextAfter: [SubtitleCue]
    public let sourceCharacterCount: Int
    /// Whole-file plot summary and glossary shared by every batch, so parallel
    /// batches stay consistent without depending on each other's output.
    public var contextSummary: String?

    public init(
        id: Int,
        batchNumber: Int,
        totalBatches: Int,
        focusedCues: [SubtitleCue],
        contextBefore: [SubtitleCue],
        contextAfter: [SubtitleCue],
        sourceCharacterCount: Int,
        contextSummary: String? = nil
    ) {
        self.id = id
        self.batchNumber = batchNumber
        self.totalBatches = totalBatches
        self.focusedCues = focusedCues
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.sourceCharacterCount = sourceCharacterCount
        self.contextSummary = contextSummary
    }

    public func withContextSummary(_ summary: String?) -> TranslationBatch {
        var copy = self
        copy.contextSummary = summary
        return copy
    }

    public func replacingFocusedCues(_ cues: [SubtitleCue]) -> TranslationBatch {
        TranslationBatch(
            id: id,
            batchNumber: batchNumber,
            totalBatches: totalBatches,
            focusedCues: cues,
            contextBefore: contextBefore,
            contextAfter: contextAfter,
            sourceCharacterCount: cues.reduce(0) { $0 + $1.text.count + $1.timecode.count },
            contextSummary: contextSummary
        )
    }

    public var expectedIDs: [Int] {
        focusedCues.map(\.sequence)
    }
}
