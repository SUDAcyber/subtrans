import Foundation
import SubtitleForgeCore

struct SubtitleDocument: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var sourceURL: URL?
    var importedAt: Date
    var rawByteCount: Int
    var targetLanguage: String
    var cues: [SubtitleCue]
    var generatedURL: URL?
    var deletedAt: Date?
    var reviewCueIDs: Set<Int>

    init(
        id: UUID = UUID(),
        name: String,
        sourceURL: URL?,
        importedAt: Date = Date(),
        rawByteCount: Int,
        targetLanguage: String,
        cues: [SubtitleCue],
        generatedURL: URL? = nil,
        deletedAt: Date? = nil,
        reviewCueIDs: Set<Int> = []
    ) {
        self.id = id
        self.name = name
        self.sourceURL = sourceURL
        self.importedAt = importedAt
        self.rawByteCount = rawByteCount
        self.targetLanguage = targetLanguage
        self.cues = cues
        self.generatedURL = generatedURL
        self.deletedAt = deletedAt
        self.reviewCueIDs = reviewCueIDs
    }

    var translatedCount: Int {
        cues.filter(\.hasTranslation).count
    }

    var completionFraction: Double {
        guard !cues.isEmpty else { return 0 }
        return Double(translatedCount) / Double(cues.count)
    }

    var displayByteSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(rawByteCount), countStyle: .file)
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    var hasReviewWarnings: Bool {
        !reviewCueIDs.isEmpty
    }
}

struct TranslationProgress: Equatable {
    enum Phase: String {
        case idle
        case parsing
        case translating
        case validating
        case finished
        case cancelled
        case failed
    }

    var phase: Phase = .idle
    var currentBatch: Int = 0
    var totalBatches: Int = 0
    var message: String = "待命"

    var fraction: Double {
        guard totalBatches > 0 else { return 0 }
        return min(1, Double(currentBatch) / Double(totalBatches))
    }
}

struct ValidationReport: Equatable {
    var totalCues: Int = 0
    var translatedCues: Int = 0
    var missingIDs: [Int] = []
    var duplicateIDs: [Int] = []

    var isComplete: Bool {
        totalCues > 0 && missingIDs.isEmpty && duplicateIDs.isEmpty && translatedCues == totalCues
    }

    var summary: String {
        if totalCues == 0 { return "未导入" }
        if isComplete { return "完整" }
        if !duplicateIDs.isEmpty { return "序号重复 \(duplicateIDs.count)" }
        if !missingIDs.isEmpty { return "缺失 \(missingIDs.count)" }
        return "\(translatedCues)/\(totalCues)"
    }

    static func make(cues: [SubtitleCue]) -> ValidationReport {
        let grouped = Dictionary(grouping: cues, by: \.sequence)
        let duplicateIDs = grouped
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
        let missing = cues
            .filter { !$0.hasTranslation }
            .map(\.sequence)
        return ValidationReport(
            totalCues: cues.count,
            translatedCues: cues.filter(\.hasTranslation).count,
            missingIDs: missing,
            duplicateIDs: duplicateIDs
        )
    }
}
