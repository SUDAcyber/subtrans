import Foundation

public struct TranslationBatch: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let batchNumber: Int
    public let totalBatches: Int
    public let focusedCues: [SubtitleCue]
    public let contextBefore: [SubtitleCue]
    public let contextAfter: [SubtitleCue]
    public let sourceCharacterCount: Int

    public init(
        id: Int,
        batchNumber: Int,
        totalBatches: Int,
        focusedCues: [SubtitleCue],
        contextBefore: [SubtitleCue],
        contextAfter: [SubtitleCue],
        sourceCharacterCount: Int
    ) {
        self.id = id
        self.batchNumber = batchNumber
        self.totalBatches = totalBatches
        self.focusedCues = focusedCues
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.sourceCharacterCount = sourceCharacterCount
    }

    public var expectedIDs: [Int] {
        focusedCues.map(\.sequence)
    }
}
