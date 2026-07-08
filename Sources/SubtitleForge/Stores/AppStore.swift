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
    private var historySaveTask: Task<Void, Never>?

    var documents: [SubtitleDocument] = DocumentHistoryStore.load() {
        didSet {
            scheduleHistorySave()
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
    var interfaceLanguage = UserPreferencesStore.loadInterfaceLanguage() {
        didSet {
            UserPreferencesStore.saveInterfaceLanguage(interfaceLanguage)
            if progress.phase == .idle {
                progress.message = strings.idle
            }
        }
    }
    var progress = TranslationProgress()
    var validation = ValidationReport()
    var errorMessage: String?
    var isInspectorPresented = true
    var isFindReplacePresented = false
    var replacementSearchText = ""
    var replacementText = ""
    var replacementMatchCase = false
    var previewCueLimit = UserPreferencesStore.loadPreviewCueLimit() {
        didSet {
            UserPreferencesStore.savePreviewCueLimit(previewCueLimit)
        }
    }
    var colorSchemeMode = UserPreferencesStore.loadColorSchemeMode() {
        didSet {
            UserPreferencesStore.saveColorSchemeMode(colorSchemeMode)
        }
    }

    init(client: any SubtitleTranslationClient = OpenAICompatibleClient()) {
        self.client = client
        self.apiKey = keychain.loadAPIKey()
        self.progress.message = strings.idle
        emptyExpiredTrash()
        self.selectedDocumentID = activeDocuments.first?.id ?? trashedDocuments.first?.id
        if let selectedDocument {
            self.validation = ValidationReport.make(cues: selectedDocument.cues)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.historySaveTask?.cancel()
                DocumentHistoryStore.save(self.documents)
            }
        }
    }

    var strings: AppStrings {
        AppStrings(language: interfaceLanguage)
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
        panel.prompt = strings.importAction
        panel.message = strings.selectSubtitleFiles

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
        progress = TranslationProgress(phase: .parsing, message: strings.parsing)
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
        progress = TranslationProgress(phase: .idle, message: strings.imported(count: cues.count))
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
                        self.errorMessage = self.strings.unreadableDroppedFile
                        return
                    }
                    guard url.pathExtension.lowercased() == "srt" else {
                        self.errorMessage = self.strings.onlySRTDrop
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
            errorMessage = strings.importFileFirst
            return
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = strings.fillAPIKey
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
        progress = TranslationProgress(phase: .cancelled, message: strings.stopped)
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
        progress = TranslationProgress(phase: .idle, message: strings.translationsCleared)
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
        progress = TranslationProgress(phase: .idle, message: strings.movedToTrash)
    }

    func restoreDocument(id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].deletedAt = nil
        selectedDocumentID = id
        validation = ValidationReport.make(cues: documents[index].cues)
        progress = TranslationProgress(phase: .idle, message: strings.restored)
    }

    func permanentlyDeleteDocument(id: UUID) {
        documents.removeAll { $0.id == id }
        if selectedDocumentID == id {
            selectedDocumentID = activeDocuments.first?.id ?? trashedDocuments.first?.id
        }
        progress = TranslationProgress(phase: .idle, message: strings.permanentlyDeleted)
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
            errorMessage = strings.importFileFirst
            return
        }
        let needle = replacementSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            errorMessage = strings.enterSearchText
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
            progress = TranslationProgress(phase: .idle, message: strings.replacedOne())
            return
        }

        errorMessage = strings.noTranslationMatch
    }

    func replaceAllTranslationMatches() {
        guard let documentIndex = selectedDocumentIndex else {
            errorMessage = strings.importFileFirst
            return
        }
        let needle = replacementSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            errorMessage = strings.enterSearchText
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
        progress = TranslationProgress(phase: .idle, message: strings.replacedAll(replacements))
    }

    func addMemoryEntry(source: String, target: String, note: String = "") {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty, !trimmedTarget.isEmpty else {
            errorMessage = strings.memoryNeedsSourceAndTarget
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
            errorMessage = strings.noExportableSubtitle
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.srtSubtitle]
        panel.nameFieldStringValue = "\(document.name)-\(settings.targetLanguage).srt"
        panel.prompt = strings.export

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = SRTParser.render(document.cues, preferTranslations: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            if let index = selectedDocumentIndex {
                documents[index].generatedURL = url
            }
            progress = TranslationProgress(phase: .finished, message: strings.exported)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportSelectedToSourceFolder() {
        guard let index = selectedDocumentIndex else {
            errorMessage = strings.noExportableSubtitle
            return
        }
        do {
            let url = try writeVersionToSourceFolder(documentIndex: index)
            progress = TranslationProgress(phase: .finished, message: strings.generated(url.lastPathComponent))
        } catch ExportError.missingSourceFolder {
            errorMessage = strings.missingSourceFolder
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
        // Only untranslated cues are batched, so re-running translate after a
        // partial failure fills in exactly the missing lines.
        var batches = SRTChunker.makeBatches(
            cues: sourceCues,
            maxCueCount: settings.chunkCueLimit,
            maxSourceCharacters: settings.maxSourceCharacters,
            contextOverlap: settings.contextOverlap,
            skipTranslated: true
        )

        guard !batches.isEmpty else {
            let alreadyDone = sourceCues.contains(where: \.hasTranslation)
            progress = alreadyDone
                ? TranslationProgress(phase: .finished, message: strings.alreadyComplete)
                : TranslationProgress(phase: .failed, message: strings.noTranslatableSubtitles)
            return
        }

        // One up-front whole-file analysis (plot summary + glossary) shared by all
        // batches keeps names and tone consistent even though batches run in parallel.
        if settings.useContextAnalysis {
            progress = TranslationProgress(
                phase: .translating,
                currentBatch: 0,
                totalBatches: batches.count,
                message: strings.analyzingContext
            )
            let sample = Self.analysisSample(from: sourceCues)
            if let summary = try? await client.analyzeContext(sourceText: sample, settings: settings, apiKey: apiKey) {
                batches = batches.map { $0.withContextSummary(summary) }
            }
            if Task.isCancelled {
                progress = TranslationProgress(phase: .cancelled, message: strings.stopped)
                return
            }
        }

        progress = TranslationProgress(
            phase: .translating,
            currentBatch: 0,
            totalBatches: batches.count,
            message: strings.startTranslating
        )

        let maxConcurrent = min(max(1, settings.maxConcurrentRequests), batches.count)
        let clientRef = client
        var completed = 0
        var lastFailureMessage: String?

        do {
            try await withThrowingTaskGroup(of: BatchOutcome.self) { group in
                var nextIndex = 0
                func enqueueNext(into group: inout ThrowingTaskGroup<BatchOutcome, Error>) {
                    guard nextIndex < batches.count else { return }
                    let batch = batches[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        try await Self.translateResilient(
                            batch: batch,
                            settings: settings,
                            apiKey: apiKey,
                            client: clientRef
                        )
                    }
                }

                for _ in 0..<maxConcurrent {
                    enqueueNext(into: &group)
                }

                while let outcome = try await group.next() {
                    enqueueNext(into: &group)
                    apply(translations: outcome.translations, to: documentID)
                    refreshValidation(for: documentID)
                    completed += 1
                    if let failure = outcome.errorDescription {
                        lastFailureMessage = failure
                    }
                    progress = TranslationProgress(
                        phase: .translating,
                        currentBatch: completed,
                        totalBatches: batches.count,
                        message: strings.translatingProgress(completed: completed, total: batches.count)
                    )
                }
            }

            refreshValidation(for: documentID)
            markReviewWarnings(for: documentID, settings: settings)

            if validation.isComplete {
                var completionMessage = strings.translationComplete
                if let index = documents.firstIndex(where: { $0.id == documentID }),
                   let url = try? writeVersionToSourceFolder(documentIndex: index) {
                    completionMessage = strings.completeGenerated(url.lastPathComponent)
                }
                progress = TranslationProgress(
                    phase: .finished,
                    currentBatch: batches.count,
                    totalBatches: batches.count,
                    message: completionMessage
                )
            } else {
                progress = TranslationProgress(
                    phase: .finished,
                    currentBatch: batches.count,
                    totalBatches: batches.count,
                    message: strings.finishedMissing(count: validation.missingIDs.count)
                )
                if let lastFailureMessage {
                    errorMessage = lastFailureMessage
                }
            }
        } catch is CancellationError {
            refreshValidation(for: documentID)
            progress = TranslationProgress(phase: .cancelled, message: strings.stopped)
        } catch {
            refreshValidation(for: documentID)
            progress = TranslationProgress(phase: .failed, message: strings.failed)
            errorMessage = error.localizedDescription
        }
    }

    private struct BatchOutcome: Sendable {
        var translations: [Int: String] = [:]
        var errorDescription: String?
    }

    /// Translates one batch with layered fallbacks, mirroring the strategy used by
    /// subtitle-translator-electron: accept partial results, re-request only the
    /// missing IDs, and split the batch in half when the output is truncated or
    /// malformed. Throws only on cancellation; other failures come back as an
    /// outcome so sibling batches keep running.
    private nonisolated static func translateResilient(
        batch: TranslationBatch,
        settings: TranslationSettings,
        apiKey: String,
        client: any SubtitleTranslationClient,
        depth: Int = 0
    ) async throws -> BatchOutcome {
        var outcome = BatchOutcome()
        var pending = batch.focusedCues
        let attempts = max(1, settings.retryLimit + 1)

        for attempt in 0..<attempts {
            try Task.checkCancellation()
            do {
                let request = attempt == 0 ? batch : batch.replacingFocusedCues(pending)
                let result = try await client.translate(batch: request, settings: settings, apiKey: apiKey)
                outcome.translations.merge(result.translations) { _, new in new }
                pending = pending.filter { outcome.translations[$0.sequence] == nil }
                if pending.isEmpty {
                    outcome.errorDescription = nil
                    return outcome
                }
                // Partial response: next attempt requests only the missing cues.
                outcome.errorDescription = TranslationResultParserError
                    .missingIDs(pending.map(\.sequence)).localizedDescription
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                let splittable: Bool
                switch error {
                case OpenAICompatibleClientError.truncatedResponse:
                    splittable = true
                case is TranslationResultParserError:
                    splittable = true
                default:
                    splittable = false
                }

                if splittable, pending.count > 1, depth < 4 {
                    let mid = pending.count / 2
                    let left = batch.replacingFocusedCues(Array(pending[..<mid]))
                    let right = batch.replacingFocusedCues(Array(pending[mid...]))
                    async let leftOutcome = translateResilient(
                        batch: left, settings: settings, apiKey: apiKey, client: client, depth: depth + 1
                    )
                    async let rightOutcome = translateResilient(
                        batch: right, settings: settings, apiKey: apiKey, client: client, depth: depth + 1
                    )
                    let (l, r) = try await (leftOutcome, rightOutcome)
                    outcome.translations.merge(l.translations) { _, new in new }
                    outcome.translations.merge(r.translations) { _, new in new }
                    outcome.errorDescription = l.errorDescription ?? r.errorDescription
                    return outcome
                }

                outcome.errorDescription = error.localizedDescription
                if attempt + 1 < attempts {
                    try await Task.sleep(nanoseconds: 600_000_000 * UInt64(attempt + 1))
                }
            }
        }

        // Last resort for cues the model keeps skipping (filler words, symbols):
        // request each one individually so it cannot be omitted from a larger batch.
        if !pending.isEmpty, pending.count <= 16 {
            for cue in pending {
                try Task.checkCancellation()
                let single = batch.replacingFocusedCues([cue])
                if let result = try? await client.translate(batch: single, settings: settings, apiKey: apiKey),
                   let text = result.translations[cue.sequence] {
                    outcome.translations[cue.sequence] = text
                }
            }
            pending = pending.filter { outcome.translations[$0.sequence] == nil }
            outcome.errorDescription = pending.isEmpty
                ? nil
                : TranslationResultParserError.missingIDs(pending.map(\.sequence)).localizedDescription
        }

        return outcome
    }

    private nonisolated static func analysisSample(from cues: [SubtitleCue], maxCharacters: Int = 12_000) -> String {
        var lines: [String] = []
        var total = 0
        // Sample evenly across the whole file so the summary covers the full story arc.
        let stride = max(1, cues.count * 40 / max(1, maxCharacters))
        var index = 0
        while index < cues.count, total < maxCharacters {
            let text = cues[index].text
            lines.append(text)
            total += text.count + 1
            index += stride
        }
        return lines.joined(separator: "\n")
    }

    private func scheduleHistorySave() {
        historySaveTask?.cancel()
        let snapshot = documents
        historySaveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            DocumentHistoryStore.save(snapshot)
        }
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
