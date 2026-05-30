import Foundation

public enum TranslationResultParserError: Error, Equatable, LocalizedError {
    case missingJSON
    case invalidJSON
    case missingIDs([Int])
    case unexpectedIDs([Int])

    public var errorDescription: String? {
        switch self {
        case .missingJSON:
            return "模型返回内容中没有找到 JSON"
        case .invalidJSON:
            return "模型返回 JSON 格式无效"
        case let .missingIDs(ids):
            return "模型漏译了字幕序号：\(ids.map(String.init).joined(separator: ", "))"
        case let .unexpectedIDs(ids):
            return "模型返回了不属于当前分段的字幕序号：\(ids.map(String.init).joined(separator: ", "))"
        }
    }
}

public enum TranslationResultParser {
    public static func parse(
        _ content: String,
        expectedIDs: [Int],
        stripPunctuation: Bool
    ) throws -> [Int: String] {
        let json = try extractJSON(from: content)
        let data = Data(json.utf8)
        let decoder = JSONDecoder()

        let items: [TranslationItem]
        if let object = try? decoder.decode(TranslationEnvelope.self, from: data) {
            items = object.translations
        } else if let array = try? decoder.decode([TranslationItem].self, from: data) {
            items = array
        } else {
            throw TranslationResultParserError.invalidJSON
        }

        var translations: [Int: String] = [:]
        for item in items {
            translations[item.id] = stripPunctuation
                ? sanitizeSubtitleText(item.text)
                : item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let expected = Set(expectedIDs)
        let returned = Set(translations.keys)
        let missing = expected.subtracting(returned).sorted()
        let unexpected = returned.subtracting(expected).sorted()

        guard missing.isEmpty else {
            throw TranslationResultParserError.missingIDs(missing)
        }
        guard unexpected.isEmpty else {
            throw TranslationResultParserError.unexpectedIDs(unexpected)
        }

        return translations
    }

    private static func extractJSON(from content: String) throws -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return trimmed
        }

        if let fenced = trimmed.range(of: "```") {
            var body = String(trimmed[fenced.upperBound...])
            if body.hasPrefix("json") {
                body.removeFirst(4)
            }
            if let endFence = body.range(of: "```") {
                return String(body[..<endFence.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let start = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }),
           let end = trimmed.lastIndex(where: { $0 == "}" || $0 == "]" }),
           start <= end {
            return String(trimmed[start...end])
        }

        throw TranslationResultParserError.missingJSON
    }

    private static func sanitizeSubtitleText(_ text: String) -> String {
        let punctuation = CharacterSet(charactersIn: "，。！？、；：,.!?;:\"“”‘’（）()【】[]《》<>…—-")
            .union(.init(charactersIn: "\u{3000}"))
        let scalars = text.unicodeScalars.map { scalar -> String in
            punctuation.contains(scalar) ? " " : String(scalar)
        }
        return scalars.joined()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct TranslationEnvelope: Decodable {
    let translations: [TranslationItem]
}

private struct TranslationItem: Decodable {
    let id: Int
    let text: String
}
