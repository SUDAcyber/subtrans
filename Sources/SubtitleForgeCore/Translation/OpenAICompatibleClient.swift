import Foundation

public enum OpenAICompatibleClientError: Error, LocalizedError {
    case invalidBaseURL(String)
    case emptyAPIKey
    case emptyModel
    case emptyResponse
    case httpError(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidBaseURL(value):
            return "接口地址无效：\(value)"
        case .emptyAPIKey:
            return "请先填写 API Key"
        case .emptyModel:
            return "请先填写模型名称"
        case .emptyResponse:
            return "模型返回为空"
        case let .httpError(statusCode, message):
            return "接口请求失败 \(statusCode)：\(message)"
        }
    }
}

public protocol SubtitleTranslationClient: Sendable {
    func translate(
        batch: TranslationBatch,
        settings: TranslationSettings,
        apiKey: String
    ) async throws -> [Int: String]
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
    ) async throws -> [Int: String] {
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

        return try TranslationResultParser.parse(
            content,
            expectedIDs: batch.expectedIDs,
            stripPunctuation: settings.stripTargetPunctuation
        )
    }

    private func chatCompletion(
        batch: TranslationBatch,
        settings: TranslationSettings,
        apiKey: String
    ) async throws -> String {
        let url = try endpointURL(baseURL: settings.baseURL, path: "chat/completions")
        let system = TranslationPromptBuilder.systemPrompt(settings: settings)
        let user = try TranslationPromptBuilder.userPrompt(batch: batch, settings: settings)

        let body: [String: Any] = [
            "model": settings.model,
            "temperature": settings.temperature,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]

        let data = try await postJSON(body, to: url, apiKey: apiKey, timeout: settings.requestTimeoutSeconds)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = response.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw OpenAICompatibleClientError.emptyResponse
        }
        return content
    }

    private func responses(
        batch: TranslationBatch,
        settings: TranslationSettings,
        apiKey: String
    ) async throws -> String {
        let url = try endpointURL(baseURL: settings.baseURL, path: "responses")
        let system = TranslationPromptBuilder.systemPrompt(settings: settings)
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
            let content: String
        }

        let message: Message
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
