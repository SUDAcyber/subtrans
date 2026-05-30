import Foundation

public enum TranslationPromptBuilderError: Error, LocalizedError {
    case encodingFailed

    public var errorDescription: String? {
        "无法构造模型请求"
    }
}

public enum TranslationPromptBuilder {
    public static func systemPrompt(settings: TranslationSettings) -> String {
        """
        \(settings.promptTemplate)

        Output rules:
        Return JSON only.
        The JSON schema is {"translations":[{"id":1,"text":"translated subtitle"}]}.
        Return exactly one item for every focused cue id.
        Do not include markdown fences or extra commentary.
        Never change cue ids.
        """
    }

    public static func userPrompt(batch: TranslationBatch, settings: TranslationSettings) throws -> String {
        let payload = BatchPromptPayload(
            targetLanguage: settings.targetLanguage,
            batchNumber: batch.batchNumber,
            totalBatches: batch.totalBatches,
            contextBefore: batch.contextBefore.map(PromptCue.init),
            focusedCues: batch.focusedCues.map(PromptCue.init),
            contextAfter: batch.contextAfter.map(PromptCue.init)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8)
        else {
            throw TranslationPromptBuilderError.encodingFailed
        }

        return """
        Translate only focusedCues into \(settings.targetLanguage).
        Use contextBefore and contextAfter only for meaning and continuity.
        Return translations for focusedCues only.

        \(json)
        """
    }
}

private struct BatchPromptPayload: Encodable {
    let targetLanguage: String
    let batchNumber: Int
    let totalBatches: Int
    let contextBefore: [PromptCue]
    let focusedCues: [PromptCue]
    let contextAfter: [PromptCue]
}

private struct PromptCue: Encodable {
    let id: Int
    let timecode: String
    let text: String

    init(_ cue: SubtitleCue) {
        id = cue.sequence
        timecode = cue.timecode
        text = cue.text
    }
}
