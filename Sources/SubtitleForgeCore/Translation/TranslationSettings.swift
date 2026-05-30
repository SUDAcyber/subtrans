import Foundation

public enum TranslationEndpoint: String, CaseIterable, Codable, Identifiable, Sendable {
    case chatCompletions
    case responses

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chatCompletions:
            return "Chat Completions"
        case .responses:
            return "Responses"
        }
    }
}

public enum ReasoningEffort: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case low
    case medium
    case high

    public var id: String { rawValue }
}

public enum TextVerbosity: String, CaseIterable, Codable, Identifiable, Sendable {
    case low
    case medium
    case high

    public var id: String { rawValue }
}

public struct TranslationSettings: Codable, Equatable, Sendable {
    public var providerName: String
    public var baseURL: String
    public var model: String
    public var endpoint: TranslationEndpoint
    public var targetLanguage: String
    public var temperature: Double
    public var reasoningEffort: ReasoningEffort
    public var textVerbosity: TextVerbosity
    public var chunkCueLimit: Int
    public var maxSourceCharacters: Int
    public var contextOverlap: Int
    public var retryLimit: Int
    public var requestTimeoutSeconds: Double
    public var stripTargetPunctuation: Bool
    public var promptTemplate: String

    public init(
        providerName: String = "AIHubMix",
        baseURL: String = "https://aihubmix.com/v1",
        model: String = "gpt-5.5",
        endpoint: TranslationEndpoint = .chatCompletions,
        targetLanguage: String = "简体中文",
        temperature: Double = 0.4,
        reasoningEffort: ReasoningEffort = .medium,
        textVerbosity: TextVerbosity = .low,
        chunkCueLimit: Int = 60,
        maxSourceCharacters: Int = 6_000,
        contextOverlap: Int = 6,
        retryLimit: Int = 2,
        requestTimeoutSeconds: Double = 120,
        stripTargetPunctuation: Bool = true,
        promptTemplate: String = TranslationSettings.defaultPrompt
    ) {
        self.providerName = providerName
        self.baseURL = baseURL
        self.model = model
        self.endpoint = endpoint
        self.targetLanguage = targetLanguage
        self.temperature = temperature
        self.reasoningEffort = reasoningEffort
        self.textVerbosity = textVerbosity
        self.chunkCueLimit = chunkCueLimit
        self.maxSourceCharacters = maxSourceCharacters
        self.contextOverlap = contextOverlap
        self.retryLimit = retryLimit
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.stripTargetPunctuation = stripTargetPunctuation
        self.promptTemplate = promptTemplate
    }

    public static var aiHubMixDefault: TranslationSettings {
        TranslationSettings()
    }

    public static let defaultPrompt = """
    # Role
    你是一位精通中英文及多语种的资深影视字幕翻译专家 你具备深厚的语言功底 能够准确理解源语言的俚语 文化梗和语境 并将其翻译成地道 流畅 简洁的目标语言

    # Task
    请将输入的 SRT 字幕文本翻译成目标语言

    # Constraints & Rules
    1 严禁修改序号 cue id 和时间轴 本应用会在本地重建 SRT 你只输出对应 id 的译文
    2 仅翻译字幕文本 不要解释 不要总结 不要补充
    3 如果目标语言是中文 译文中严禁出现标点符号 句内停顿使用一个空格代替 句末不需要任何符号或空格
    4 译文要口语化 简洁 自然 避免翻译腔
    5 必须结合上下文 不要逐字直译
    6 人名地名使用常见通译 如果不确定请保留原文
    7 省略无意义的 uh um ah 等语气词 除非它们对剧情表达至关重要
    """
}
