import XCTest
@testable import SubtitleForgeCore

final class LunaModelResolutionTests: XCTestCase {
    func testLunaBaseMapsEffortToVariants() {
        let none = OpenAICompatibleClient.resolvedChatModel(model: "gpt-5.6-luna", effort: .none)
        XCTAssertEqual(none.model, "gpt-5.6-luna")
        XCTAssertFalse(none.sendsReasoningEffort)

        let low = OpenAICompatibleClient.resolvedChatModel(model: "gpt-5.6-luna", effort: .low)
        XCTAssertEqual(low.model, "gpt-5.6-luna-low")

        let medium = OpenAICompatibleClient.resolvedChatModel(model: "gpt-5.6-luna", effort: .medium)
        XCTAssertEqual(medium.model, "gpt-5.6-luna-high")

        let high = OpenAICompatibleClient.resolvedChatModel(model: "gpt-5.6-luna", effort: .high)
        XCTAssertEqual(high.model, "gpt-5.6-luna-high")
    }

    func testExplicitLunaVariantIsKeptAsIs() {
        let resolved = OpenAICompatibleClient.resolvedChatModel(model: "gpt-5.6-luna-low", effort: .high)
        XCTAssertEqual(resolved.model, "gpt-5.6-luna-low")
        XCTAssertFalse(resolved.sendsReasoningEffort)
    }

    func testNonLunaModelsSendReasoningEffort() {
        let resolved = OpenAICompatibleClient.resolvedChatModel(model: "gpt-5.5", effort: .medium)
        XCTAssertEqual(resolved.model, "gpt-5.5")
        XCTAssertTrue(resolved.sendsReasoningEffort)
    }
}
