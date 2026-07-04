import Foundation

public enum SRTChunker {
    public static func makeBatches(
        cues: [SubtitleCue],
        maxCueCount: Int,
        maxSourceCharacters: Int,
        contextOverlap: Int,
        skipTranslated: Bool = false
    ) -> [TranslationBatch] {
        guard !cues.isEmpty else { return [] }

        let cueLimit = max(1, maxCueCount)
        let characterLimit = max(500, maxSourceCharacters)
        let overlap = max(0, contextOverlap)

        let pendingIndices = skipTranslated
            ? cues.indices.filter { !cues[$0].hasTranslation }
            : Array(cues.indices)
        guard !pendingIndices.isEmpty else { return [] }

        // Group pending cues into batches by count and character budget.
        var groups: [[Int]] = []
        var group: [Int] = []
        var characterCount = 0

        for index in pendingIndices {
            let cue = cues[index]
            let cueCost = cue.text.count + cue.timecode.count + 24
            let wouldExceedCount = group.count >= cueLimit
            let wouldExceedCharacters = characterCount + cueCost > characterLimit

            if !group.isEmpty && (wouldExceedCount || wouldExceedCharacters) {
                groups.append(group)
                group = []
                characterCount = 0
            }

            group.append(index)
            characterCount += cueCost
        }
        if !group.isEmpty {
            groups.append(group)
        }

        return groups.enumerated().map { offset, indices in
            let first = indices.first ?? cues.startIndex
            let last = indices.last ?? first
            let beforeStart = Swift.max(cues.startIndex, first - overlap)
            let afterEnd = Swift.min(cues.endIndex, last + 1 + overlap)
            let focused = indices.map { cues[$0] }
            let before = first > beforeStart ? Array(cues[beforeStart..<first]) : []
            let after = afterEnd > last + 1 ? Array(cues[(last + 1)..<afterEnd]) : []
            let sourceCharacterCount = focused.reduce(0) { total, cue in
                total + cue.text.count + cue.timecode.count
            }

            return TranslationBatch(
                id: offset + 1,
                batchNumber: offset + 1,
                totalBatches: groups.count,
                focusedCues: focused,
                contextBefore: before,
                contextAfter: after,
                sourceCharacterCount: sourceCharacterCount
            )
        }
    }
}
