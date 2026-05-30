import Foundation

enum DocumentHistoryStore {
    private static let fileName = "document-history.json"

    static func load() -> [SubtitleDocument] {
        guard let url = historyURL(),
              let data = try? Data(contentsOf: url),
              let documents = try? JSONDecoder().decode([SubtitleDocument].self, from: data)
        else {
            return []
        }
        return documents
    }

    static func save(_ documents: [SubtitleDocument]) {
        guard let url = historyURL() else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(documents)
            try data.write(to: url, options: .atomic)
        } catch {
            // History is a convenience cache. Translation/export should never fail because this write failed.
        }
    }

    private static func historyURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent("字幕锻造", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
