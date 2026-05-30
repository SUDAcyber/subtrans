import Foundation

public enum SRTChunker {
    public static func makeBatches(
        cues: [SubtitleCue],
        maxCueCount: Int,
        maxSourceCharacters: Int,
        contextOverlap: Int
    ) -> [TranslationBatch] {
        guard !cues.isEmpty else { return [] }

        let cueLimit = max(1, maxCueCount)
        let characterLimit = max(500, maxSourceCharacters)
        let overlap = max(0, contextOverlap)

        var ranges: [Range<Int>] = []
        var start = cues.startIndex

        while start < cues.endIndex {
            var end = start
            var characterCount = 0

            while end < cues.endIndex {
                let cue = cues[end]
                let cueCost = cue.text.count + cue.timecode.count + 24
                let cueCount = end - start
                let wouldExceedCount = cueCount >= cueLimit
                let wouldExceedCharacters = characterCount + cueCost > characterLimit

                if end > start && (wouldExceedCount || wouldExceedCharacters) {
                    break
                }

                characterCount += cueCost
                end += 1
            }

            ranges.append(start..<end)
            start = end
        }

        return ranges.enumerated().map { offset, range in
            let beforeStart = Swift.max(cues.startIndex, range.lowerBound - overlap)
            let afterEnd = Swift.min(cues.endIndex, range.upperBound + overlap)
            let focused = Array(cues[range])
            let before = range.lowerBound > beforeStart ? Array(cues[beforeStart..<range.lowerBound]) : []
            let after = afterEnd > range.upperBound ? Array(cues[range.upperBound..<afterEnd]) : []
            let sourceCharacterCount = focused.reduce(0) { total, cue in
                total + cue.text.count + cue.timecode.count
            }

            return TranslationBatch(
                id: offset + 1,
                batchNumber: offset + 1,
                totalBatches: ranges.count,
                focusedCues: focused,
                contextBefore: before,
                contextAfter: after,
                sourceCharacterCount: sourceCharacterCount
            )
        }
    }
}
