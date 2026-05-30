import Foundation
import SubtitleForgeCore

enum UserPreferencesStore {
    private static let settingsKey = "subtitleForge.translationSettings"
    private static let previewCueLimitKey = "subtitleForge.previewCueLimit"

    static func loadSettings() -> TranslationSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(TranslationSettings.self, from: data)
        else {
            return .aiHubMixDefault
        }
        return settings
    }

    static func saveSettings(_ settings: TranslationSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }

    static func loadPreviewCueLimit() -> Int {
        let value = UserDefaults.standard.integer(forKey: previewCueLimitKey)
        return value > 0 ? value : 800
    }

    static func savePreviewCueLimit(_ value: Int) {
        UserDefaults.standard.set(value, forKey: previewCueLimitKey)
    }
}
