import Foundation

enum DocumentHistoryStore {
    private static let fileName = "document-history.json"
    private static let appFolderName = AppPaths.supportFolderName
    private static let legacyAppFolderName = "字幕锻造"
    /// Serializes writes so a debounced background save and the synchronous
    /// terminate-time save can never interleave; the last submitted write wins.
    private static let saveQueue = DispatchQueue(label: "com.subtitleforge.history-save")

    static func load() -> [SubtitleDocument] {
        guard let url = readableHistoryURL(),
              let data = try? Data(contentsOf: url),
              let documents = try? JSONDecoder().decode([SubtitleDocument].self, from: data)
        else {
            return []
        }
        migrateLegacyHistoryIfNeeded(from: url)
        return documents
    }

    /// Background debounced save: enqueue and return.
    static func save(_ documents: [SubtitleDocument]) {
        saveQueue.async { write(documents) }
    }

    /// Blocks until the write (and any queued writes ahead of it) complete. Used
    /// at app termination so the final state is guaranteed on disk.
    static func saveSynchronously(_ documents: [SubtitleDocument]) {
        saveQueue.sync { write(documents) }
    }

    private static func write(_ documents: [SubtitleDocument]) {
        guard let url = historyURL(folderName: appFolderName) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(documents)
            try data.write(to: url, options: .atomic)
        } catch {
            // History is a convenience cache. Translation/export should never fail because this write failed.
        }
    }

    private static func readableHistoryURL() -> URL? {
        guard let newURL = historyURL(folderName: appFolderName) else { return nil }
        if FileManager.default.fileExists(atPath: newURL.path) {
            return newURL
        }
        guard let legacyURL = historyURL(folderName: legacyAppFolderName),
              FileManager.default.fileExists(atPath: legacyURL.path)
        else {
            return newURL
        }
        return legacyURL
    }

    private static func migrateLegacyHistoryIfNeeded(from sourceURL: URL) {
        guard sourceURL.deletingLastPathComponent().lastPathComponent == legacyAppFolderName,
              let newURL = historyURL(folderName: appFolderName),
              !FileManager.default.fileExists(atPath: newURL.path)
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: newURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: sourceURL, to: newURL)
        } catch {
            // History migration is best effort. Loading from the legacy path is still valid.
        }
    }

    private static func historyURL(folderName: String) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
