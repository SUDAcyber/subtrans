import Foundation

enum DiskUsage {
    /// Recursive on-disk size of a directory in bytes (0 if missing).
    static func directorySize(_ directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Locations of the downloadable Whisper CoreML models (WhisperKit's default
/// download base is ~/Documents/huggingface).
enum WhisperModelStore {
    static var modelsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }

    static func totalSizeBytes() -> Int64 {
        guard let directory = modelsDirectory else { return 0 }
        return DiskUsage.directorySize(directory)
    }

    static func clearAll() {
        guard let directory = modelsDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
