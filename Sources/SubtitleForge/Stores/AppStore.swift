import AppKit
import Foundation
import Observation
import SubtitleForgeCore
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppStore {
    private let keychain = KeychainService()
    private let client: any SubtitleTranslationClient
    private var translationTask: Task<Void, Never>?

    var documents: [SubtitleDocument] = []
    var selectedDocumentID: UUID?
    var settings = UserPreferencesStore.loadSettings() {
        didSet {
            UserPreferencesStore.saveSettings(settings)
        }
    }
    var apiKey = "" {
        didSet {
            keychain.saveAPIKey(apiKey)
        }
    }
    var progress = TranslationProgress()
    var validation = ValidationReport()
    var errorMessage: String?
    var isInspectorPresented = true
    var previewCueLimit = UserPreferencesStore.loadPreviewCueLimit() {
        didSet {
            UserPreferencesStore.savePreviewCueLimit(previewCueLimit)
        }
    }

    init(client: any SubtitleTranslationClient = OpenAICompatibleClient()) {
        self.client = client
        self.apiKey = keychain.loadAPIKey()
    }

    var selectedDocument: SubtitleDocument? {
        guard let selectedDocumentID else { return nil }
        return documents.first { $0.id == selectedDocumentID }
    }

    var selectedDocumentIndex: Int? {
        guard let selectedDocumentID else { return nil }
        return documents.firstIndex { $0.id == selectedDocumentID }
    }

    var canTranslate: Bool {
        selectedDocument != nil && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isTranslating
    }

    var isTranslating: Bool {
        progress.phase == .translating || progress.phase == .validating
    }

    func saveAPIKey() {
        keychain.saveAPIKey(apiKey)
    }

    func applyAIHubMixPreset() {
        settings.providerName = "AIHubMix"
        settings.baseURL = "https://aihubmix.com/v1"
        if settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.model = "gpt-5.5"
        }
        UserPreferencesStore.saveSettings(settings)
    }

    func applyOpenAIPreset() {
        settings.providerName = "OpenAI"
        settings.baseURL = "https://api.openai.com/v1"
        if settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.model = "gpt-5.5"
        }
        UserPreferencesStore.saveSettings(settings)
    }

    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.srtSubtitle, .plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "导入"
        panel.message = "选择一个或多个 SRT 字幕文件"

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do {
                try importFile(url: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func importFile(url: URL) throws {
        progress = TranslationProgress(phase: .parsing, message: "正在解析")
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let text = try TextFileDecoder.decode(data)
        let cues = try SRTParser.parse(text)
        let document = SubtitleDocument(
            name: url.deletingPathExtension().lastPathComponent,
            sourceURL: url,
            rawByteCount: data.count,
            targetLanguage: settings.targetLanguage,
            cues: cues
        )
        documents.insert(document, at: 0)
        selectedDocumentID = document.id
        validation = ValidationReport.make(cues: cues)
        progress = TranslationProgress(phase: .idle, message: "已导入 \(cues.count) 条")
    }

    func importDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
                let droppedURL = Self.fileURL(from: item)
                let droppedErrorMessage = error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let droppedErrorMessage {
                        self.errorMessage = droppedErrorMessage
                        return
                    }
                    guard let url = droppedURL else {
                        self.errorMessage = "无法读取拖入的文件"
                        return
                    }
                    guard url.pathExtension.lowercased() == "srt" else {
                        self.errorMessage = "目前只支持拖入 SRT 字幕文件"
                        return
                    }

                    do {
                        try self.importFile(url: url)
                    } catch {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }

        return true
    }

    func translateSelected() {
        guard !isTranslating else { return }
        guard let document = selectedDocument else {
            errorMessage = "请先导入字幕文件"
            return
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请先在右侧填写密钥"
            isInspectorPresented = true
            return
        }

        let settingsSnapshot = settings
        let apiKeySnapshot = apiKey
        let documentID = document.id
        let sourceCues = document.cues
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            await self?.performTranslation(
                documentID: documentID,
                sourceCues: sourceCues,
                settings: settingsSnapshot,
                apiKey: apiKeySnapshot
            )
        }
    }

    func cancelTranslation() {
        translationTask?.cancel()
        translationTask = nil
        progress = TranslationProgress(phase: .cancelled, message: "已停止")
    }

    func clearTranslations() {
        guard let index = selectedDocumentIndex else { return }
        for cueIndex in documents[index].cues.indices {
            documents[index].cues[cueIndex].translation = nil
        }
        validation = ValidationReport.make(cues: documents[index].cues)
        progress = TranslationProgress(phase: .idle, message: "译文已清空")
    }

    func exportSelectedWithPanel() {
        guard let document = selectedDocument else {
            errorMessage = "没有可导出的字幕"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.srtSubtitle]
        panel.nameFieldStringValue = "\(document.name)-\(settings.targetLanguage).srt"
        panel.prompt = "导出"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = SRTParser.render(document.cues, preferTranslations: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            progress = TranslationProgress(phase: .finished, message: "已导出")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performTranslation(
        documentID: UUID,
        sourceCues: [SubtitleCue],
        settings: TranslationSettings,
        apiKey: String
    ) async {
        let batches = SRTChunker.makeBatches(
            cues: sourceCues,
            maxCueCount: settings.chunkCueLimit,
            maxSourceCharacters: settings.maxSourceCharacters,
            contextOverlap: settings.contextOverlap
        )

        guard !batches.isEmpty else {
            progress = TranslationProgress(phase: .failed, message: "没有可翻译的字幕")
            return
        }

        progress = TranslationProgress(
            phase: .translating,
            currentBatch: 0,
            totalBatches: batches.count,
            message: "开始翻译"
        )

        do {
            for batch in batches {
                try Task.checkCancellation()
                let translations = try await translateWithRetry(
                    batch: batch,
                    settings: settings,
                    apiKey: apiKey
                )
                apply(translations: translations, to: documentID)
                progress = TranslationProgress(
                    phase: .validating,
                    currentBatch: batch.batchNumber,
                    totalBatches: batches.count,
                    message: "校验第 \(batch.batchNumber)/\(batches.count) 批"
                )
                refreshValidation(for: documentID)
                progress.phase = .translating
            }

            refreshValidation(for: documentID)
            progress = TranslationProgress(
                phase: .finished,
                currentBatch: batches.count,
                totalBatches: batches.count,
                message: validation.isComplete ? "翻译完成" : "完成但仍有缺失"
            )
        } catch is CancellationError {
            progress = TranslationProgress(phase: .cancelled, message: "已停止")
        } catch {
            progress = TranslationProgress(phase: .failed, message: "失败")
            errorMessage = error.localizedDescription
        }
    }

    private func translateWithRetry(
        batch: TranslationBatch,
        settings: TranslationSettings,
        apiKey: String
    ) async throws -> [Int: String] {
        var lastError: Error?
        let attempts = max(0, settings.retryLimit)

        for attempt in 0...attempts {
            do {
                progress = TranslationProgress(
                    phase: .translating,
                    currentBatch: batch.batchNumber - 1,
                    totalBatches: batch.totalBatches,
                    message: attempt == 0
                        ? "翻译第 \(batch.batchNumber)/\(batch.totalBatches) 批"
                        : "重试第 \(batch.batchNumber) 批 \(attempt)/\(attempts)"
                )
                return try await client.translate(batch: batch, settings: settings, apiKey: apiKey)
            } catch {
                lastError = error
                if attempt < attempts {
                    let delay = UInt64(600_000_000) * UInt64(attempt + 1)
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }

        throw lastError ?? OpenAICompatibleClientError.emptyResponse
    }

    private func apply(translations: [Int: String], to documentID: UUID) {
        guard let documentIndex = documents.firstIndex(where: { $0.id == documentID }) else { return }
        for (id, text) in translations {
            guard let cueIndex = documents[documentIndex].cues.firstIndex(where: { $0.sequence == id }) else {
                continue
            }
            documents[documentIndex].cues[cueIndex].translation = text
        }
    }

    private func refreshValidation(for documentID: UUID) {
        guard let document = documents.first(where: { $0.id == documentID }) else { return }
        validation = ValidationReport.make(cues: document.cues)
    }

    private nonisolated static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data {
            if let url = URL(dataRepresentation: data, relativeTo: nil) {
                return url
            }
            if let string = String(data: data, encoding: .utf8) {
                return fileURL(from: string)
            }
        }
        if let string = item as? String {
            return fileURL(from: string)
        }
        return nil
    }

    private nonisolated static func fileURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        return URL(fileURLWithPath: trimmed)
    }
}
