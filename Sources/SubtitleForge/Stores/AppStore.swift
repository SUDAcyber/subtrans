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

    var documents: [SubtitleDocument] = DocumentHistoryStore.load() {
        didSet {
            DocumentHistoryStore.save(documents)
        }
    }
    var selectedDocumentID: UUID? {
        didSet {
            if let selectedDocument {
                validation = ValidationReport.make(cues: selectedDocument.cues)
            }
        }
    }
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
    var replacementSearchText = ""
    var replacementText = ""
    var replacementMatchCase = false
    var previewCueLimit = UserPreferencesStore.loadPreviewCueLimit() {
        didSet {
            UserPreferencesStore.savePreviewCueLimit(previewCueLimit)
        }
    }

    init(client: any SubtitleTranslationClient = OpenAICompatibleClient()) {
        self.client = client
        self.apiKey = keychain.loadAPIKey()
        emptyExpiredTrash()
        self.selectedDocumentID = activeDocuments.first?.id ?? trashedDocuments.first?.id
        if let selectedDocument {
            self.validation = ValidationReport.make(cues: selectedDocument.cues)
        }
    }

    var selectedDocument: SubtitleDocument? {
        guard let selectedDocumentID else { return nil }
        return documents.first { $0.id == selectedDocumentID }
    }

    var selectedDocumentIndex: Int? {
        guard let selectedDocumentID else { return nil }
        return documents.firstIndex { $0.id == selectedDocumentID }
    }

    var activeDocuments: [SubtitleDocument] {
        documents.filter { !$0.isDeleted }
    }

    var trashedDocuments: [SubtitleDocument] {
        documents.filter(\.isDeleted)
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var canTranslate: Bool {
        selectedDocument?.isDeleted == false
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isTranslating
    }

    var replacementMatchCount: Int {
        guard let document = selectedDocument else { return 0 }
        let needle = replacementSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return 0 }

        return document.cues.reduce(0) { total, cue in
            guard let translation = cue.translation else { return total }
            return total + translation.matchCount(of: needle, matchCase: replacementMatchCase)
        }
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
        guard !documents[index].isDeleted else { return }
        for cueIndex in documents[index].cues.indices {
            documents[index].cues[cueIndex].translation = nil
        }
        documents[index].generatedURL = nil
        documents[index].reviewCueIDs = []
        validation = ValidationReport.make(cues: documents[index].cues)
        progress = TranslationProgress(phase: .idle, message: "译文已清空")
    }

    func moveSelectedToTrash() {
        guard let id = selectedDocumentID else { return }
        moveDocumentToTrash(id: id)
    }

    func moveDocumentToTrash(id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].deletedAt = Date()
        if selectedDocumentID == id {
            selectedDocumentID = activeDocuments.first?.id ?? trashedDocuments.first?.id
        }
        progress = TranslationProgress(phase: .idle, message: "已移到回收箱")
    }

    func restoreDocument(id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].deletedAt = nil
        selectedDocumentID = id
        validation = ValidationReport.make(cues: documents[index].cues)
        progress = TranslationProgress(phase: .idle, message: "已恢复")
    }

    func permanentlyDeleteDocument(id: UUID) {
        documents.removeAll { $0.id == id }
        if selectedDocumentID == id {
            selectedDocumentID = activeDocuments.first?.id ?? trashedDocuments.first?.id
        }
        progress = TranslationProgress(phase: .idle, message: "已永久删除")
    }

    func emptyExpiredTrash(now: Date = Date()) {
        let expiration = Calendar.current.date(byAdding: .day, value: -15, to: now) ?? now
        documents.removeAll { document in
            guard let deletedAt = document.deletedAt else { return false }
            return deletedAt < expiration
        }
    }

    func replaceOneTranslationMatch() {
        guard let documentIndex = selectedDocumentIndex else {
            errorMessage = "请先导入字幕文件"
            return
        }
        let needle = replacementSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            errorMessage = "请先输入要查找的译文"
            return
        }

        for cueIndex in documents[documentIndex].cues.indices {
            guard let translation = documents[documentIndex].cues[cueIndex].translation,
                  let updated = translation.replacingFirstOccurrence(
                    of: needle,
                    with: replacementText,
                    matchCase: replacementMatchCase
                  )
            else {
                continue
            }

            documents[documentIndex].cues[cueIndex].translation = updated
            refreshValidation(for: documents[documentIndex].id)
            progress = TranslationProgress(phase: .idle, message: "已替换 1 处")
            return
        }

        errorMessage = "没有找到匹配译文"
    }

    func replaceAllTranslationMatches() {
        guard let documentIndex = selectedDocumentIndex else {
            errorMessage = "请先导入字幕文件"
            return
        }
        let needle = replacementSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            errorMessage = "请先输入要查找的译文"
            return
        }

        var replacements = 0
        for cueIndex in documents[documentIndex].cues.indices {
            guard let translation = documents[documentIndex].cues[cueIndex].translation else {
                continue
            }
            let count = translation.matchCount(of: needle, matchCase: replacementMatchCase)
            guard count > 0 else { continue }
            documents[documentIndex].cues[cueIndex].translation = translation.replacingAllOccurrences(
                of: needle,
                with: replacementText,
                matchCase: replacementMatchCase
            )
            replacements += count
        }

        refreshValidation(for: documents[documentIndex].id)
        progress = TranslationProgress(phase: .idle, message: replacements > 0 ? "已替换 \(replacements) 处" : "没有找到匹配译文")
    }

    func addMemoryEntry(source: String, target: String, note: String = "") {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty, !trimmedTarget.isEmpty else {
            errorMessage = "记忆库需要同时填写原文和固定译法"
            return
        }

        if let index = settings.translationMemory.firstIndex(where: { $0.source.caseInsensitiveCompare(trimmedSource) == .orderedSame }) {
            settings.translationMemory[index].target = trimmedTarget
            settings.translationMemory[index].note = note
        } else {
            settings.translationMemory.append(
                TranslationMemoryEntry(source: trimmedSource, target: trimmedTarget, note: note)
            )
        }
    }

    func removeMemoryEntry(id: TranslationMemoryEntry.ID) {
        settings.translationMemory.removeAll { $0.id == id }
    }

    func restoreDefaultMemoryEntries() {
        var merged = settings.translationMemory
        for defaultEntry in TranslationSettings.defaultTranslationMemory {
            if let index = merged.firstIndex(where: { $0.source.caseInsensitiveCompare(defaultEntry.source) == .orderedSame }) {
                merged[index] = defaultEntry
            } else {
                merged.append(defaultEntry)
            }
        }
        settings.translationMemory = merged
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
            if let index = selectedDocumentIndex {
                documents[index].generatedURL = url
            }
            progress = TranslationProgress(phase: .finished, message: "已导出")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportSelectedToSourceFolder() {
        guard let index = selectedDocumentIndex else {
            errorMessage = "没有可导出的字幕"
            return
        }
        do {
            let url = try writeVersionToSourceFolder(documentIndex: index)
            progress = TranslationProgress(phase: .finished, message: "已生成 \(url.lastPathComponent)")
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
            markReviewWarnings(for: documentID, settings: settings)
            var completionMessage = validation.isComplete ? "翻译完成" : "完成但仍有缺失"
            if validation.isComplete,
               let index = documents.firstIndex(where: { $0.id == documentID }),
               let url = try? writeVersionToSourceFolder(documentIndex: index) {
                completionMessage = "翻译完成 已生成 \(url.lastPathComponent)"
            }
            progress = TranslationProgress(
                phase: .finished,
                currentBatch: batches.count,
                totalBatches: batches.count,
                message: completionMessage
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

    private func writeVersionToSourceFolder(documentIndex: Int) throws -> URL {
        guard let sourceURL = documents[documentIndex].sourceURL else {
            throw ExportError.missingSourceFolder
        }
        let directory = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let language = documents[documentIndex].targetLanguage
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let baseOutput = "\(baseName)-\(language)"
        let outputURL = uniqueOutputURL(directory: directory, baseName: baseOutput)
        let text = SRTParser.render(documents[documentIndex].cues, preferTranslations: true)
        try text.write(to: outputURL, atomically: true, encoding: .utf8)
        documents[documentIndex].generatedURL = outputURL
        return outputURL
    }

    private func uniqueOutputURL(directory: URL, baseName: String) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).srt")
        var version = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-v\(version).srt")
            version += 1
        }
        return candidate
    }

    private func markReviewWarnings(for documentID: UUID, settings: TranslationSettings) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return }
        let protectedNames = Set(
            settings.translationMemory.flatMap { [$0.source.normalizedNameKey, $0.target.normalizedNameKey] }
        )
        let warningIDs = documents[index].cues.compactMap { cue -> Int? in
            let candidates = cue.text.probableNameCandidates()
                .filter { !protectedNames.contains($0.normalizedNameKey) }
            return candidates.isEmpty ? nil : cue.sequence
        }
        documents[index].reviewCueIDs = Set(warningIDs)
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

private enum ExportError: LocalizedError {
    case missingSourceFolder

    var errorDescription: String? {
        switch self {
        case .missingSourceFolder:
            return "这个字幕没有原始文件夹信息 请使用导出字幕选择保存位置"
        }
    }
}

private extension String {
    func matchCount(of needle: String, matchCase: Bool) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchStart = startIndex
        let options: String.CompareOptions = matchCase ? [] : [.caseInsensitive]

        while searchStart < endIndex,
              let range = range(of: needle, options: options, range: searchStart..<endIndex) {
            count += 1
            searchStart = range.upperBound
        }

        return count
    }

    func replacingFirstOccurrence(of needle: String, with replacement: String, matchCase: Bool) -> String? {
        let options: String.CompareOptions = matchCase ? [] : [.caseInsensitive]
        guard let range = range(of: needle, options: options) else { return nil }
        var copy = self
        copy.replaceSubrange(range, with: replacement)
        return copy
    }

    func replacingAllOccurrences(of needle: String, with replacement: String, matchCase: Bool) -> String {
        let options: String.CompareOptions = matchCase ? [] : [.caseInsensitive]
        return replacingOccurrences(of: needle, with: replacement, options: options)
    }
}

private extension String {
    var normalizedNameKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func probableNameCandidates() -> [String] {
        let words = components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let stopwords: Set<String> = [
            "I", "A", "The", "This", "That", "These", "Those", "Did", "Do", "Does", "Is", "Are", "Was", "Were",
            "Can", "Could", "Would", "Should", "Will", "May", "Maybe", "Yes", "No", "Not", "And", "But", "Or",
            "If", "Then", "When", "Where", "Why", "How", "What", "Who", "Please", "Mom", "Dad", "Sir", "Mr", "Ms"
        ]

        var candidates: [String] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            if word.isProbableNameWord && !stopwords.contains(word) {
                var phrase = word
                if index + 1 < words.count {
                    let next = words[index + 1]
                    if next.isProbableNameWord && !stopwords.contains(next) {
                        phrase += " \(next)"
                        index += 1
                    }
                }
                candidates.append(phrase)
            }
            index += 1
        }
        return candidates
    }

    var isProbableNameWord: Bool {
        guard count >= 3,
              let first = unicodeScalars.first,
              CharacterSet.uppercaseLetters.contains(first)
        else {
            return false
        }
        return unicodeScalars.dropFirst().contains { CharacterSet.lowercaseLetters.contains($0) }
    }
}
