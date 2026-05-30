import XCTest
@testable import SubtitleForgeCore

final class TranslationPromptBuilderTests: XCTestCase {
    func testSystemPromptIncludesMemoryAndProperNameProtection() {
        var settings = TranslationSettings.aiHubMixDefault
        settings.translationMemory = [
            TranslationMemoryEntry(source: "Ko Song", target: "Ko Song", note: "人名"),
            TranslationMemoryEntry(source: "เซิร์ฟ", target: "Surf", note: "泰语人名")
        ]

        let prompt = TranslationPromptBuilder.systemPrompt(settings: settings)
        XCTAssertTrue(prompt.contains("Ko Song => Ko Song"))
        XCTAssertTrue(prompt.contains("เซิร์ฟ => Surf"))
        XCTAssertTrue(prompt.contains("Never translate the literal meaning of romanized personal names"))
        XCTAssertTrue(prompt.contains("不能翻译成二哥"))
    }
}
