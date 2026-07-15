import XCTest
@testable import SubtitleForgeCore

final class SpeechVocabularyTests: XCTestCase {
    func testPromptUsesSourceSpellingAndSkipsNonLatin() {
        let memory = [
            TranslationMemoryEntry(source: "Surf", target: "Surf"),          // romanized, kept
            TranslationMemoryEntry(source: "Type", target: "泰普"),          // source is romanized → keep source, not 泰普
            TranslationMemoryEntry(source: "เซิร์ฟ", target: "Surf"),        // Thai source → skipped
            TranslationMemoryEntry(source: "小明", target: "Xiao Ming"),     // CJK source → skipped
            TranslationMemoryEntry(source: "", target: "Empty")             // unusable
        ]
        let prompt = SpeechVocabulary.prompt(from: memory)
        XCTAssertEqual(prompt, "Surf, Type")
        XCTAssertFalse(prompt?.contains("泰普") ?? true)
        XCTAssertFalse(prompt?.contains("เซิร์ฟ") ?? true)
    }

    func testPromptDedupesCaseInsensitivelyAndCaps() {
        let memory = (0..<50).map { TranslationMemoryEntry(source: "Name\($0)", target: "t") }
            + [TranslationMemoryEntry(source: "surf", target: "s"), TranslationMemoryEntry(source: "SURF", target: "s")]
        let prompt = SpeechVocabulary.prompt(from: memory, limit: 40)
        let count = prompt?.split(separator: ",").count ?? 0
        XCTAssertEqual(count, 40)
    }

    func testPromptNilWhenNoRomanizedNames() {
        let memory = [TranslationMemoryEntry(source: "泰语", target: "Thai")]
        XCTAssertNil(SpeechVocabulary.prompt(from: memory))
    }

    func testIsRomanized() {
        XCTAssertTrue(SpeechVocabulary.isRomanized("Ko Song"))
        XCTAssertTrue(SpeechVocabulary.isRomanized("José"))
        XCTAssertFalse(SpeechVocabulary.isRomanized("小明"))
        XCTAssertFalse(SpeechVocabulary.isRomanized("เซิร์ฟ"))
        XCTAssertFalse(SpeechVocabulary.isRomanized("123"))
    }

    func testVersionComparison() {
        XCTAssertTrue(SemanticVersion.isNewer("0.5.0", than: "0.4.1"))
        XCTAssertTrue(SemanticVersion.isNewer("v0.4.10", than: "0.4.9"))
        XCTAssertFalse(SemanticVersion.isNewer("0.4.1", than: "0.4.1"))
        XCTAssertFalse(SemanticVersion.isNewer("0.4.0", than: "0.4.1"))
        XCTAssertTrue(SemanticVersion.isNewer("1.0", than: "0.9.9"))
    }
}
