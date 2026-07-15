import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum AudioExtractorError: LocalizedError {
    case noAudioTrack
    case unsupportedMKV
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "这个文件里没有音轨 / No audio track in this file"
        case .unsupportedMKV:
            return "暂不支持 MKV 容器（macOS AVFoundation 无法解析）请先用 ffmpeg 转为 MP4 或提取为 M4A/WAV 再导入 / MKV is not supported by macOS AVFoundation. Convert to MP4 or extract M4A/WAV with ffmpeg first."
        case let .exportFailed(reason):
            return "音轨提取失败 / Audio extraction failed: \(reason)"
        }
    }
}

enum AudioExtractor {
    static let audioExtensions: Set<String> = ["mp3", "wav", "m4a", "aac", "flac", "aiff", "caf"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mpg", "mpeg", "ts", "mkv"]

    static func isMediaFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if audioExtensions.contains(ext) || videoExtensions.contains(ext) {
            return true
        }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .audio)
            || type.conforms(to: .movie)
            || type.conforms(to: .audiovisualContent)
    }

    /// Returns a local audio file for the given media URL. Audio files pass through
    /// unchanged; video containers get their audio track exported to M4A.
    static func extractAudioIfNeeded(from url: URL) async throws -> URL {
        let ext = url.pathExtension.lowercased()
        if ext == "mkv" {
            throw AudioExtractorError.unsupportedMKV
        }
        if audioExtensions.contains(ext) {
            return url
        }

        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw AudioExtractorError.noAudioTrack
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubtitleForge-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioExtractorError.exportFailed("无法创建导出会话")
        }
        session.outputURL = outputURL
        session.outputFileType = .m4a

        await session.export()
        switch session.status {
        case .completed:
            return outputURL
        case .cancelled:
            throw CancellationError()
        default:
            throw AudioExtractorError.exportFailed(session.error?.localizedDescription ?? "未知错误")
        }
    }
}
