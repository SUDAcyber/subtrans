import Foundation
import SubtitleForgeCore
import WhisperKit

/// Local on-device transcription via WhisperKit (CoreML on the Apple Neural Engine).
/// The pipeline is non-Sendable, so all use of it stays inside this actor; the
/// loaded model is cached so repeated runs skip the load cost.
actor WhisperKitEngine {
    static let shared = WhisperKitEngine()
    static let idleUnloadDelay: Duration = .seconds(600)

    private var pipeline: WhisperKit?
    private var loadedModel: String?
    private var idleUnloadTask: Task<Void, Never>?

    var transcriptionFraction: Double {
        pipeline?.progress.fractionCompleted ?? 0
    }

    func transcribe(
        model: String,
        audioPath: String,
        languageHint: String?,
        onDownloadProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscribedSegment] {
        idleUnloadTask?.cancel()
        let pipeline = try await loadPipeline(model: model, onDownloadProgress: onDownloadProgress)
        defer { scheduleIdleUnload() }

        var options = DecodingOptions()
        options.task = .transcribe
        options.skipSpecialTokens = true
        options.chunkingStrategy = .vad
        if let languageHint, !languageHint.isEmpty, languageHint != "auto" {
            options.language = languageHint
        } else {
            options.detectLanguage = true
        }

        let results = try await pipeline.transcribe(
            audioPath: audioPath,
            decodeOptions: options,
            callback: { _ in
                Task.isCancelled ? false : nil
            }
        )

        let segments = results
            .flatMap(\.segments)
            .map { segment in
                TranscribedSegment(
                    start: Double(segment.start),
                    end: Double(segment.end),
                    text: segment.text
                )
            }
        return segments
    }

    private func loadPipeline(
        model: String,
        onDownloadProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> WhisperKit {
        if let pipeline, loadedModel == model {
            return pipeline
        }
        if let pipeline {
            await pipeline.unloadModels()
        }
        pipeline = nil
        loadedModel = nil

        let modelFolder: URL
        if let bundled = Self.bundledModelFolder(named: model) {
            modelFolder = bundled
            onDownloadProgress(1)
        } else {
            modelFolder = try await WhisperKit.download(variant: model) { progress in
                onDownloadProgress(progress.fractionCompleted)
            }
        }
        let config = WhisperKitConfig(
            model: model,
            modelFolder: modelFolder.path,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )
        let created = try await WhisperKit(config)
        pipeline = created
        loadedModel = model
        return created
    }

    private static func bundledModelFolder(named model: String) -> URL? {
        let candidates = [Bundle.main.resourceURL, Bundle.module.resourceURL]
            .compactMap { $0?.appendingPathComponent("WhisperModels/\(model)", isDirectory: true) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleUnloadDelay)
            guard !Task.isCancelled else { return }
            await self?.unloadPipeline()
        }
    }

    private func unloadPipeline() async {
        guard let pipeline else { return }
        await pipeline.unloadModels()
        pipeline.clearState()
        self.pipeline = nil
        loadedModel = nil
    }
}

struct WhisperKitTranscriber: SubtitleTranscriber {
    let model: String

    func transcribe(
        audioURL: URL,
        languageHint: String?,
        onProgress: @escaping @Sendable (TranscriptionProgressUpdate) -> Void
    ) async throws -> [TranscribedSegment] {
        onProgress(.preparingModel)

        let poller = Task {
            while !Task.isCancelled {
                let fraction = await WhisperKitEngine.shared.transcriptionFraction
                if fraction > 0 {
                    onProgress(.transcribing(fraction: min(0.999, fraction)))
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        defer { poller.cancel() }

        return try await WhisperKitEngine.shared.transcribe(
            model: model,
            audioPath: audioURL.path,
            languageHint: languageHint,
            onDownloadProgress: { fraction in
                onProgress(.downloadingModel(fraction: fraction))
            }
        )
    }
}
