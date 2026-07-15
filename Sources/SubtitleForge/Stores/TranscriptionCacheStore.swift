import CryptoKit
import Foundation
import SubtitleForgeCore

/// Disk cache for transcription results, keyed by media-file fingerprint plus the
/// engine configuration. A crashed or cancelled session can re-import the same
/// video and skip transcription entirely.
enum TranscriptionCacheStore {
    private static let folderName = "\(AppPaths.supportFolderName)/transcription-cache"
    private static let maxEntries = 60
    /// Serializes disk I/O so it never blocks the main actor and prune/save cannot race.
    private static let ioQueue = DispatchQueue(label: "com.subtitleforge.transcription-cache")

    struct Key {
        let fingerprint: String?

        /// Snapshots the file's size/mtime at construction time (before
        /// transcription reads it), so save() cannot fingerprint a file that
        /// changed mid-transcription under its post-run state.
        init(mediaURL: URL, engine: TranscriptionEngine, model: String, language: String, vocabulary: String?) {
            guard let values = try? mediaURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize
            else {
                self.fingerprint = nil
                return
            }
            let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            // The Whisper model only affects output for the whisperKit engine.
            let modelPart = engine == .whisperKit ? model : ""
            let raw = "\(mediaURL.path)|\(size)|\(modified)|\(engine.rawValue)|\(modelPart)|\(language)|\(vocabulary ?? "")"
            let digest = SHA256.hash(data: Data(raw.utf8))
            self.fingerprint = digest.map { String(format: "%02x", $0) }.joined() + ".json"
        }

        fileprivate var fileName: String? { fingerprint }
    }

    static func load(for key: Key) -> [TranscribedSegment]? {
        guard let url = cacheURL(for: key) else { return nil }
        return ioQueue.sync {
            guard let data = try? Data(contentsOf: url),
                  let segments = try? JSONDecoder().decode([TranscribedSegment].self, from: data),
                  !segments.isEmpty
            else {
                return nil
            }
            // Touch mtime so the prune step is LRU, not FIFO-by-save: a reused
            // entry survives longer than a never-reused one.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return segments
        }
    }

    /// Persists off the main actor; returns immediately.
    static func save(_ segments: [TranscribedSegment], for key: Key) {
        guard let url = cacheURL(for: key), !segments.isEmpty else { return }
        ioQueue.async {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try JSONEncoder().encode(segments)
                try data.write(to: url, options: .atomic)
                pruneIfNeeded(directory: url.deletingLastPathComponent())
            } catch {
                // Cache is best effort; transcription already succeeded.
            }
        }
    }

    /// Total bytes used by cached transcripts (off-main; call from a background task).
    static func totalSizeBytes() -> Int64 {
        guard let directory = cacheDirectory() else { return 0 }
        return ioQueue.sync { DiskUsage.directorySize(directory) }
    }

    /// Removes every cached transcript.
    static func clearAll() {
        guard let directory = cacheDirectory() else { return }
        ioQueue.async {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func cacheDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private static func cacheURL(for key: Key) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let fileName = key.fileName
        else {
            return nil
        }
        return base
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private static func pruneIfNeeded(directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ), files.count > maxEntries else {
            return
        }
        let sorted = files.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }
        for stale in sorted.prefix(files.count - maxEntries) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}
