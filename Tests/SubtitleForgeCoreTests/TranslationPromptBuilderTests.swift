import XCTest
@testable import SubtitleForgeCore

final class TranslationPromptBuilderTests: XCTestCase {
    func testSystemPromptIncludesMemoryAndProperNameProtection() {
        var settings = TranslationSettings.aiHubMixDefault
        settings.translationMemory = [
            TranslationMemoryEntry(source: "Source Name A", target: "Target Name A", note: "test fixture"),
            TranslationMemoryEntry(source: "Source Term B", target: "Target Term B", note: "test fixture")
        ]

        let prompt = TranslationPromptBuilder.systemPrompt(settings: settings)
        XCTAssertTrue(prompt.contains("Source Name A => Target Name A"))
        XCTAssertTrue(prompt.contains("Source Term B => Target Term B"))
        XCTAssertTrue(prompt.contains("Never translate the literal meaning of romanized personal names"))
        XCTAssertTrue(prompt.contains("不要按字面意思翻译"))
    }
}
