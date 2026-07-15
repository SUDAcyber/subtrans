import Foundation

/// Single source of truth for the app's on-disk locations. Renaming the support
/// folder must happen here (and in Resources/install_typhoon.sh, which cannot
/// reference Swift constants).
enum AppPaths {
    static let supportFolderName = "SUDA字幕翻译助手"

    static var supportDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(supportFolderName, isDirectory: true)
    }
}
