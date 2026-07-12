import Foundation

public enum TranslationEndpoint: String, CaseIterable, Codable, Identifiable, Sendable {
    case chatCompletions
    case responses

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chatCompletions:
            return "聊天补全"
        case .responses:
            return "Responses 接口"
        }
    }
}

public enum ReasoningEffort: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case low
    case medium
    case high

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none:
            return "模型默认"
        case .low:
            return "低"
        case .medium:
            return "中"
        case .high:
            return "高"
        }
    }
}

public enum TextVerbosity: String, CaseIterable, Codable, Identifiable, Sendable {
    case low
    case medium
    case high

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .low:
            return "短"
        case .medium:
            return "中"
        case .high:
            return "长"
        }
    }
}

public struct TranslationMemoryEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var source: String
    public var target: String
    public var note: String

    public init(
        id: UUID = UUID(),
        source: String,
        target: String,
        note: String = ""
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.note = note
    }

    public var isUsable: Bool {
        !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct TranslationSettings: Codable, Equatable, Sendable {
    public var providerName: String
    public var baseURL: String
    public var model: String
    public var endpoint: TranslationEndpoint
    public var targetLanguage: String
    public var reasoningEffort: ReasoningEffort
    public var textVerbosity: TextVerbosity
    public var chunkCueLimit: Int
    public var maxSourceCharacters: Int
    public var contextOverlap: Int
    public var retryLimit: Int
    public var requestTimeoutSeconds: Double
    public var stripTargetPunctuation: Bool
    public var maxConcurrentRequests: Int
    public var useContextAnalysis: Bool
    public var transcriptionEngine: TranscriptionEngine
    public var whisperModel: String
    public var transcriptionLanguage: String
    public var promptTemplate: String
    public var translationMemory: [TranslationMemoryEntry]

    public init(
        providerName: String = "AIHubMix",
        baseURL: String = "https://aihubmix.com/v1",
        model: String = "gpt-5.6-luna",
        endpoint: TranslationEndpoint = .chatCompletions,
        targetLanguage: String = "简体中文",
        reasoningEffort: ReasoningEffort = .low,
        textVerbosity: TextVerbosity = .low,
        chunkCueLimit: Int = 24,
        maxSourceCharacters: Int = 6_000,
        contextOverlap: Int = 5,
        retryLimit: Int = 2,
        requestTimeoutSeconds: Double = 120,
        stripTargetPunctuation: Bool = true,
        maxConcurrentRequests: Int = 5,
        useContextAnalysis: Bool = true,
        transcriptionEngine: TranscriptionEngine = .whisperKit,
        whisperModel: String = "large-v3",
        transcriptionLanguage: String = "auto",
        promptTemplate: String = TranslationSettings.defaultPrompt,
        translationMemory: [TranslationMemoryEntry] = TranslationSettings.defaultTranslationMemory
    ) {
        self.providerName = providerName
        self.baseURL = baseURL
        self.model = model
        self.endpoint = endpoint
        self.targetLanguage = targetLanguage
        self.reasoningEffort = reasoningEffort
        self.textVerbosity = textVerbosity
        self.chunkCueLimit = chunkCueLimit
        self.maxSourceCharacters = maxSourceCharacters
        self.contextOverlap = contextOverlap
        self.retryLimit = retryLimit
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.stripTargetPunctuation = stripTargetPunctuation
        self.maxConcurrentRequests = maxConcurrentRequests
        self.useContextAnalysis = useContextAnalysis
        self.transcriptionEngine = transcriptionEngine
        self.whisperModel = whisperModel
        self.transcriptionLanguage = transcriptionLanguage
        self.promptTemplate = promptTemplate
        self.translationMemory = translationMemory
    }

    enum CodingKeys: String, CodingKey {
        case providerName
        case baseURL
        case model
        case endpoint
        case targetLanguage
        case reasoningEffort
        case textVerbosity
        case chunkCueLimit
        case maxSourceCharacters
        case contextOverlap
        case retryLimit
        case requestTimeoutSeconds
        case stripTargetPunctuation
        case maxConcurrentRequests
        case useContextAnalysis
        case transcriptionEngine
        case whisperModel
        case transcriptionLanguage
        case promptTemplate
        case translationMemory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.providerName = try container.decodeIfPresent(String.self, forKey: .providerName) ?? "AIHubMix"
        self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://aihubmix.com/v1"
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? "gpt-5.6-luna"
        self.endpoint = try container.decodeIfPresent(TranslationEndpoint.self, forKey: .endpoint) ?? .chatCompletions
        self.targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "简体中文"
        self.reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort) ?? .medium
        self.textVerbosity = try container.decodeIfPresent(TextVerbosity.self, forKey: .textVerbosity) ?? .low
        self.chunkCueLimit = try container.decodeIfPresent(Int.self, forKey: .chunkCueLimit) ?? 60
        self.maxSourceCharacters = try container.decodeIfPresent(Int.self, forKey: .maxSourceCharacters) ?? 6_000
        self.contextOverlap = try container.decodeIfPresent(Int.self, forKey: .contextOverlap) ?? 6
        self.retryLimit = try container.decodeIfPresent(Int.self, forKey: .retryLimit) ?? 2
        self.requestTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .requestTimeoutSeconds) ?? 120
        self.stripTargetPunctuation = try container.decodeIfPresent(Bool.self, forKey: .stripTargetPunctuation) ?? true
        self.maxConcurrentRequests = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentRequests) ?? 5
        self.useContextAnalysis = try container.decodeIfPresent(Bool.self, forKey: .useContextAnalysis) ?? true
        self.transcriptionEngine = try container.decodeIfPresent(TranscriptionEngine.self, forKey: .transcriptionEngine) ?? .whisperKit
        self.whisperModel = try container.decodeIfPresent(String.self, forKey: .whisperModel) ?? "large-v3"
        self.transcriptionLanguage = try container.decodeIfPresent(String.self, forKey: .transcriptionLanguage) ?? "auto"
        self.promptTemplate = try container.decodeIfPresent(String.self, forKey: .promptTemplate) ?? TranslationSettings.defaultPrompt
        self.translationMemory = try container.decodeIfPresent([TranslationMemoryEntry].self, forKey: .translationMemory)
            ?? TranslationSettings.defaultTranslationMemory
    }

    public static var aiHubMixDefault: TranslationSettings {
        TranslationSettings()
    }

    // Shipping builds never include a user's terminology or translation memory.
    // Entries are created locally and persisted only in the user's preferences.
    public static let defaultTranslationMemory: [TranslationMemoryEntry] = []

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
    6 人名地名优先使用常见英文通译或官方英文名 罗马字母人名和昵称默认视为专名 不要按字面意思翻译 如果目标语言有非常通用的标准译名可使用该译名 如果不确定请保留英文原文
    7 省略句中无意义的 uh um ah 等语气词 除非它们对剧情表达至关重要 但如果整条字幕只有语气词 请输出对应目标语言的简短语气词 例如 嗯 啊 不要留空也不要跳过
    """
}
