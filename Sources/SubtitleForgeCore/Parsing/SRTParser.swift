import Foundation

public enum SRTParserError: Error, Equatable, LocalizedError {
    case emptyDocument
    case malformedSequence(line: Int, value: String)
    case missingTimecode(line: Int, sequence: Int)
    case malformedTimecode(line: Int, sequence: Int, value: String)

    public var errorDescription: String? {
        switch self {
        case .emptyDocument:
            return "没有找到有效的 SRT 字幕块"
        case let .malformedSequence(line, value):
            return "第 \(line) 行不是有效的字幕序号：\(value)"
        case let .missingTimecode(line, sequence):
            return "序号 \(sequence) 在第 \(line) 行附近缺少时间轴"
        case let .malformedTimecode(line, sequence, value):
            return "序号 \(sequence) 在第 \(line) 行的时间轴格式无效：\(value)"
        }
    }
}

public enum SRTParser {
    public static func parse(_ content: String) throws -> [SubtitleCue] {
        let normalized = content
            .replacingOccurrences(of: "\u{feff}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var cues: [SubtitleCue] = []
        var index = 0

        while index < lines.count {
            while index < lines.count && lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                index += 1
            }
            guard index < lines.count else { break }

            let sequenceLineNumber = index + 1
            let sequenceValue = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let sequence = Int(sequenceValue) else {
                throw SRTParserError.malformedSequence(line: sequenceLineNumber, value: sequenceValue)
            }
            index += 1

            guard index < lines.count else {
                throw SRTParserError.missingTimecode(line: sequenceLineNumber, sequence: sequence)
            }

            let timecodeLineNumber = index + 1
            let timecodeValue = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let arrowRange = timecodeValue.range(of: "-->") else {
                throw SRTParserError.malformedTimecode(line: timecodeLineNumber, sequence: sequence, value: timecodeValue)
            }

            let startTime = timecodeValue[..<arrowRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let endTime = timecodeValue[arrowRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !startTime.isEmpty, !endTime.isEmpty else {
                throw SRTParserError.malformedTimecode(line: timecodeLineNumber, sequence: sequence, value: timecodeValue)
            }
            index += 1

            var textLines: [String] = []
            while index < lines.count {
                let value = lines[index]
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    break
                }
                textLines.append(value)
                index += 1
            }

            cues.append(
                SubtitleCue(
                    sequence: sequence,
                    startTime: String(startTime),
                    endTime: String(endTime),
                    text: textLines.joined(separator: "\n")
                )
            )
        }

        guard !cues.isEmpty else {
            throw SRTParserError.emptyDocument
        }

        return cues
    }

    public static func render(_ cues: [SubtitleCue], preferTranslations: Bool = true) -> String {
        render(cues, layout: preferTranslations ? .translationOnly : .sourceOnly)
    }

    public static func render(_ cues: [SubtitleCue], layout: SubtitleExportLayout) -> String {
        cues.map { cue in
            [
                "\(cue.sequence)",
                cue.timecode,
                renderedText(for: cue, layout: layout)
            ].joined(separator: "\n")
        }
        .joined(separator: "\n\n")
        + "\n"
    }

    private static func renderedText(for cue: SubtitleCue, layout: SubtitleExportLayout) -> String {
        let source = cue.text
        let translation = cue.hasTranslation ? cue.translation : nil
        switch layout {
        case .sourceOnly:
            return source
        case .translationOnly:
            return translation ?? source
        case .bilingualTranslationFirst:
            guard let translation else { return source }
            return "\(singleLine(translation))\n\(singleLine(source))"
        case .bilingualSourceFirst:
            guard let translation else { return source }
            return "\(singleLine(source))\n\(singleLine(translation))"
        }
    }

    /// Collapses internal line breaks so a bilingual cue stays exactly two lines
    /// (players otherwise show 3+ stacked lines that overflow the safe area).
    private static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}

public enum SubtitleExportLayout: String, CaseIterable, Codable, Identifiable, Sendable {
    case translationOnly
    case bilingualTranslationFirst
    case bilingualSourceFirst
    case sourceOnly

    public var id: String { rawValue }

    /// Layout choices exposed in export settings; sourceOnly has its own button.
    public static let exportChoices: [SubtitleExportLayout] = [
        .translationOnly, .bilingualTranslationFirst, .bilingualSourceFirst
    ]
}
