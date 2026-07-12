import Foundation

public enum OpenAICompatibleClientError: Error, LocalizedError {
    case invalidBaseURL(String)
    case emptyAPIKey
    case emptyModel
    case emptyResponse
    case truncatedResponse
    case httpError(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidBaseURL(value):
            return "接口地址无效：\(value)"
        case .emptyAPIKey:
            return "请先填写密钥"
        case .emptyModel:
            return "请先填写模型名称"
        case .emptyResponse:
            return "模型返回为空"
        case .truncatedResponse:
            return "模型输出被截断 请调小每批条数"
        case let .httpError(statusCode, message):
            return "接口请求失败 \(statusCode)：\(message)"
        }
    }
}

public protocol SubtitleTranslationClient: Sendable {
    /// Lenient translate: returns whatever valid translations came back plus the missing IDs.
    func translate(
        batch: TranslationBatch,
        settings: TranslationSettings,
        apiKey: String
    ) async throws -> PartialTranslationResult

    /// One-shot pre-analysis of the whole subtitle (plot summary + glossary) used as
    /// shared context so batches can run fully in parallel without drifting apart.
    func analyzeContext(
        sourceText: String,
        settings: TranslationSettings,
        apiKey: String
    ) async throws -> String
}

public final class OpenAICompatibleClient: SubtitleTranslationClient, @unchecked Sendable {
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func translate(
        batch: TranslationBatch,
        settings: TranslationSettings,
        apiKey: String
    ) async throws -> PartialTranslationResult {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw OpenAICompatibleClientError.emptyAPIKey }
        guard !settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAICompatibleClientError.emptyModel
        }

        let content: String
        switch settings.endpoint {
        case .chatCompletions:
            content = try await chatCompletion(batch: batch, settings: settings, apiKey: key)
        case .responses:
            content = try await responses(batch: batch, settings: settings, apiKey: key)
        }

        return try TranslationResultParser.parsePartial(
            content,
            expectedIDs: batch.expectedIDs,
            stripPunctuation: settings.stripTargetPunctuation
        )
    }

    public func analyzeContext(
        sourceText: String,
        settings: TranslationSettings,
        apiKey: String
    ) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw OpenAICompatibleClientError.emptyAPIKey }

        let system = """
        You are a subtitle content analyst assisting a translation system.
        Analyze the subtitle sample and return:
        1. Plot summary in \(settings.targetLanguage), 5-8 sentences, natural language.
        2. Glossary: up to 30 items covering character names, places, organizations, recurring jargon. \
        For each item give the source term and the preferred rendering in \(settings.targetLanguage) \
        (keep romanized personal names unchanged).
        Return plain text only, no markdown.
        """
        let user = "Subtitle sample:\n\(sourceText)"

        let url = try endpointURL(baseURL: settings.baseURL, path: "chat/completions")
        let body: [String: Any] = [
            "model": settings.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        let data = try await postJSON(body, to: url, apiKey: key, timeout: settings.requestTimeoutSeconds)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = response.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw OpenAICompatibleClientError.emptyResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resolves the model name to send to the chat-completions endpoint.
    ///
    /// gpt-5.6-luna does not accept `reasoning_effort` on chat completions — reasoning
    /// depth is selected via model variants instead (`-low` / `-high`, base = none).
    /// Returns the resolved model plus whether `reasoning_effort` may be sent.
    public static func resolvedChatModel(
        model: String,
        effort: ReasoningEffort
    ) -> (model: String, sendsReasoningEffort: Bool) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("gpt-5.6-luna") else {
            return (trimmed, true)
        }
        // Explicit variant (e.g. gpt-5.6-luna-high) is respected as-is.
        guard trimmed.lowercased() == "gpt-5.6-luna" else {
            return (trimmed, false)
        }
        switch effort {
        case .none:
            return (trimmed, false)
        case .low:
            return (trimmed + "-low", false)
        case .medium, .high:
            // Chat endpoint only offers low/high variants; medium rounds up.
            return (trimmed + "-high", false)
        }
    }

    private func chatCompletion(
        batch: TranslationBatch,
        settings: TranslationSettings,
        apiKey: String
    ) async throws -> String {
        let url = try endpointURL(baseURL: settings.baseURL, path: "chat/completions")
        let system = TranslationPromptBuilder.systemPrompt(settings: settings, contextSummary: batch.contextSummary)
        let user = try TranslationPromptBuilder.userPrompt(batch: batch, settings: settings)

        let resolved = Self.resolvedChatModel(model: settings.model, effort: settings.reasoningEffort)
        var body: [String: Any] = [
            "model": resolved.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "response_format": ["type": "json_object"]
        ]
        if resolved.sendsReasoningEffort, settings.reasoningEffort != .none {
            body["reasoning_effort"] = settings.reasoningEffort.rawValue
        }

        let data: Data
        do {
            data = try await postJSON(body, to: url, apiKey: apiKey, timeout: settings.requestTimeoutSeconds)
        } catch OpenAICompatibleClientError.httpError(400, _) {
            // Some providers reject response_format / reasoning_effort for certain
            // models; retry once with the minimal body before surfacing the error.
            body.removeValue(forKey: "response_format")
            body.removeValue(forKey: "reasoning_effort")
            data = try await postJSON(body, to: url, apiKey: apiKey, timeout: settings.requestTimeoutSeconds)
        }

        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let choice = response.choices.first,
              let content = choice.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw OpenAICompatibleClientError.emptyResponse
        }
        if choice.finishReason == "length" {
            throw OpenAICompatibleClientError.truncatedResponse
        }
        return content
    }

    private func responses(
        batch: TranslationBatch,
        settings: TranslationSettings,
        apiKey: String
    ) async throws -> String {
        let url = try endpointURL(baseURL: settings.baseURL, path: "responses")
        let system = TranslationPromptBuilder.systemPrompt(settings: settings, contextSummary: batch.contextSummary)
        let user = try TranslationPromptBuilder.userPrompt(batch: batch, settings: settings)

        var body: [String: Any] = [
            "model": settings.model,
            "input": "\(system)\n\n\(user)",
            "text": [
                "verbosity": settings.textVerbosity.rawValue
            ]
        ]

        if settings.reasoningEffort != .none {
            body["reasoning"] = [
                "effort": settings.reasoningEffort.rawValue
            ]
        }

        let data = try await postJSON(body, to: url, apiKey: apiKey, timeout: settings.requestTimeoutSeconds)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ResponsesAPIResponse.self, from: data)
        let content = response.outputText ?? response.outputTextFromContent
        guard let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAICompatibleClientError.emptyResponse
        }
        return content
    }

    private func postJSON(
        _ body: [String: Any],
        to url: URL,
        apiKey: String,
        timeout: Double
    ) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return data
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAICompatibleClientError.httpError(
                statusCode: httpResponse.statusCode,
                message: apiErrorMessage(from: data)
            )
        }

        return data
    }

    private func endpointURL(baseURL: String, path: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/\(path)") else {
            throw OpenAICompatibleClientError.invalidBaseURL(baseURL)
        }
        return url
    }

    private func apiErrorMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            return decoded.error.message
        }
        return String(data: data, encoding: .utf8) ?? "未知错误"
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]
}

private struct ResponsesAPIResponse: Decodable {
    let outputText: String?
    let output: [ResponseOutput]?

    var outputTextFromContent: String? {
        output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
    }
}

private struct ResponseOutput: Decodable {
    let content: [ResponseContent]?
}

private struct ResponseContent: Decodable {
    let text: String?
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
