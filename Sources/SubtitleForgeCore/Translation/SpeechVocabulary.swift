import Foundation

/// Pure helpers shared by the app layer, kept in Core so they are unit-testable
/// (the executable target has no test target).
public enum SpeechVocabulary {
    /// Romanized proper nouns pinned in translation memory, joined for use as a
    /// speech-recognition prompt. Uses each entry's *source* spelling (what is
    /// actually spoken in the audio) and skips non-Latin scripts (Thai/CJK/Kana/
    /// Hangul) whose presence would bias the decoder's language continuation.
    public static func prompt(from memory: [TranslationMemoryEntry], limit: Int = 40) -> String? {
        let names = memory
            .filter(\.isUsable)
            .map { $0.source.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && isRomanized($0) }
        guard !names.isEmpty else { return nil }
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0.lowercased()).inserted }
        return unique.prefix(limit).joined(separator: ", ")
    }

    /// True when the string contains a Latin letter and no CJK/Kana/Thai/Hangul.
    public static func isRomanized(_ text: String) -> Bool {
        var hasLatin = false
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x4E00...0x9FFF).contains(value)      // CJK Unified Ideographs
                || (0x3040...0x30FF).contains(value)  // Hiragana / Katakana
                || (0x0E00...0x0E7F).contains(value)  // Thai
                || (0xAC00...0xD7AF).contains(value) { // Hangul syllables
                return false
            }
            if (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) {
                hasLatin = true
            }
        }
        return hasLatin
    }
}

public enum SemanticVersion {
    /// Dotted-number comparison ("0.4.10" > "0.4.9"); non-numeric parts count as 0.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let normalize: (String) -> [Int] = { version in
            let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
            return trimmed.split(separator: ".").map { Int($0) ?? 0 }
        }
        let lhs = normalize(candidate)
        let rhs = normalize(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let l = index < lhs.count ? lhs[index] : 0
            let r = index < rhs.count ? rhs[index] : 0
            if l != r { return l > r }
        }
        return false
    }
}
