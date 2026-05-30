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
        cues.map { cue in
            [
                "\(cue.sequence)",
                cue.timecode,
                cue.renderedText(preferTranslation: preferTranslations)
            ].joined(separator: "\n")
        }
        .joined(separator: "\n\n")
        + "\n"
    }
}
