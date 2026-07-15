import AppKit
import Foundation
import Observation
import SubtitleForgeCore
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppStore {
    private let keychain = KeychainService()
    private let scribeKeychain = KeychainService(account: KeychainService.scribeAccount)
    private let client: any SubtitleTranslationClient
    private var translationTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var pendingMediaURLs: [URL] = []
    private var typhoonInstallTask: Task<Void, Never>?
    private var historySaveTask: Task<Void, Never>?
    private var updateRecheckTask: Task<Void, Never>?
    /// Monotonic id for transcription runs. A cancelled run keeps executing until
    /// its next await; comparing against this id stops it from clobbering the
    /// state of a newer run when it finally exits.
    private var transcriptionRunID = 0
    /// Same guard for translation runs, so a cancelled run's teardown cannot wipe
    /// a newer run's task handle.
    private var translationRunID = 0
    /// (documentID, sequence) pairs the user manually edited while a translation
    /// run was in flight, so incoming batch results do not clobber the edit.
    private var manualEditsDuringRun: Set<ManualEditKey> = []

    private struct ManualEditKey: Hashable {
        let documentID: UUID
        let sequence: Int
    }

    var documents: [SubtitleDocument] = DocumentHistoryStore.load() {
        didSet {
            scheduleHistorySave()
        }
    }
    var selectedDocumentID: UUID? {
        didSet {
            replacementLocatedCueSequence = nil
            if let selectedDocument {
                validation = ValidationReport.make(cues: selectedDocument.cues, threshold: settings.readingSpeedLimit)
            }
        }
    }
    var settings = UserPreferencesStore.loadSettings() {
        didSet {
            UserPreferencesStore.saveSettings(settings)
            // If the engine changed to one that is now ready, resume a queue that
            // was parked on the previous engine's missing prerequisite.
            if oldValue.transcriptionEngine != settings.transcriptionEngine {
                startNextMediaIfPossible()
            }
        }
    }
    var apiKey = "" {
        didSet {
            keychain.saveAPIKey(apiKey)
        }
    }
    var scribeAPIKey = "" {
        didSet {
            scribeKeychain.saveAPIKey(scribeAPIKey)
            // Resume a queue parked on a missing Scribe key only once the key looks
            // complete, so a half-typed key never fires a doomed request.
            let key = scribeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pendingMediaURLs.isEmpty, key.count >= 20 {
                startNextMediaIfPossible()
            }
        }
    }
    var isTranscribing = false
    var isInstallingTyphoon = false
    var typhoonInstallStatus = ""
    var pendingMediaCount = 0
    var availableUpdateVersion: String?
    var availableUpdateURL: URL?
    var availableUpdateDMG: URL?
    var isDownloadingUpdate = false
    var transcriptionCacheBytes: Int64 = 0
    var whisperModelBytes: Int64 = 0
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
    var showReviewCuesOnly = false {
        didSet { if showReviewCuesOnly { showFastCuesOnly = false } }
    }
    var showFastCuesOnly = false {
        didSet { if showFastCuesOnly { showReviewCuesOnly = false } }
    }
    var replacementSearchText = "" {
        didSet { replacementLocatedCueSequence = nil }
    }
    var replacementText = ""
    var replacementMatchCase = false {
        didSet { replacementLocatedCueSequence = nil }
    }
    var replacementLocatedCueSequence: Int?
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

    init(client: any SubtitleTranslationClient = RoutingTranslationClient()) {
        self.client = client
        self.apiKey = keychain.loadAPIKey()
        self.scribeAPIKey = scribeKeychain.loadAPIKey()
        self.progress.message = strings.idle
        emptyExpiredTrash()
        self.selectedDocumentID = activeDocuments.first?.id ?? trashedDocuments.first?.id
        if let selectedDocument {
            self.validation = ValidationReport.make(cues: selectedDocument.cues, threshold: settings.readingSpeedLimit)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.historySaveTask?.cancel()
                DocumentHistoryStore.saveSynchronously(self.documents)
            }
        }
        checkForUpdates()
        // Long-running sessions should still learn about new releases.
        updateRecheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
                guard !Task.isCancelled else { return }
                self?.checkForUpdates()
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
            && !isTranscribing
    }

    var isBusy: Bool {
        isTranslating || isTranscribing
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

    func applyProviderPreset(_ provider: TranslationProvider) {
        settings.provider = provider
        switch provider {
        case .relay:
            settings.providerName = "中转服务"
            settings.baseURL = ""
            settings.endpoint = .chatCompletions
        case .openRouter:
            settings.providerName = "OpenRouter"
            settings.baseURL = "https://openrouter.ai/api/v1"
            settings.endpoint = .chatCompletions
        case .openAI:
            settings.providerName = "OpenAI 官方"
            settings.baseURL = "https://api.openai.com/v1"
            settings.endpoint = .chatCompletions
        case .anthropic:
            settings.providerName = "Claude 官方"
            settings.baseURL = "https://api.anthropic.com"
            settings.endpoint = .chatCompletions
        }
    }

    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.srtSubtitle, .plainText, .movie, .mpeg4Movie, .quickTimeMovie, .matroskaVideo, .audio, .mp3, .wav, .mpeg4Audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = strings.importAction
        panel.message = strings.selectSubtitleFiles

        guard panel.runModal() == .OK else { return }
        handleIncoming(urls: panel.urls)
    }

    /// Single routing point for every way files enter the app (open panel, drop):
    /// media → transcription queue, SRT → immediate import, anything else → error.
    func handleIncoming(urls: [URL]) {
        var mediaURLs: [URL] = []
        for url in urls {
            if AudioExtractor.isMediaFile(url) {
                mediaURLs.append(url)
                continue
            }
            guard url.pathExtension.lowercased() == "srt" else {
                errorMessage = strings.unsupportedImportType(url.pathExtension)
                continue
            }
            do {
                try importFile(url: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        enqueueMediaFiles(mediaURLs)
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
        validation = ValidationReport.make(cues: cues, threshold: settings.readingSpeedLimit)
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
                    self.handleIncoming(urls: [url])
                }
            }
        }

        return true
    }

    func translateSelected() {
        guard !isTranslating, !isTranscribing else { return }
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
        manualEditsDuringRun.removeAll()
        translationRunID += 1
        let runID = translationRunID
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            await self?.performTranslation(
                documentID: documentID,
                sourceCues: sourceCues,
                settings: settingsSnapshot,
                apiKey: apiKeySnapshot,
                runID: runID
            )
        }
    }

    /// Stops the current transcription/translation but keeps the pending media
    /// queue intact and visible; the user resumes or clears it from the sidebar.
    func cancelTranslation() {
        translationTask?.cancel()
        translationTask = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcriptionRunID += 1
        translationRunID += 1
        isTranscribing = false
        progress = TranslationProgress(phase: .cancelled, message: strings.stopped)
    }

    func transcribeMedia(url: URL) {
        enqueueMediaFiles([url])
    }

    /// Pending media files, in processing order (read-only view for the sidebar).
    var mediaQueue: [URL] {
        pendingMediaURLs
    }

    func removeQueuedMedia(at index: Int) {
        guard pendingMediaURLs.indices.contains(index) else { return }
        pendingMediaURLs.remove(at: index)
        pendingMediaCount = pendingMediaURLs.count
    }

    func clearMediaQueue() {
        pendingMediaURLs.removeAll()
        pendingMediaCount = 0
    }

    func resumeMediaQueue() {
        startNextMediaIfPossible()
    }

    /// Recomputes cache/model disk usage off the main thread.
    func refreshCacheSizes() {
        Task.detached(priority: .utility) { [weak self] in
            let cacheBytes = TranscriptionCacheStore.totalSizeBytes()
            let modelBytes = WhisperModelStore.totalSizeBytes()
            await MainActor.run { [weak self] in
                self?.transcriptionCacheBytes = cacheBytes
                self?.whisperModelBytes = modelBytes
            }
        }
    }

    func clearTranscriptionCache() {
        TranscriptionCacheStore.clearAll()
        transcriptionCacheBytes = 0
    }

    func clearWhisperModels() {
        guard !isTranscribing else { return }
        Task.detached(priority: .utility) { [weak self] in
            WhisperModelStore.clearAll()
            await MainActor.run { [weak self] in
                self?.whisperModelBytes = 0
            }
        }
    }

    private func enqueueMediaFiles(_ urls: [URL]) {
        pendingMediaURLs.append(contentsOf: urls)
        startNextMediaIfPossible() // its defer publishes pendingMediaCount
    }

    private func startNextMediaIfPossible() {
        defer {
            // Only publish a change: @Observable notifies on every assignment,
            // triggering an unnecessary view invalidation when the count is stable.
            if pendingMediaCount != pendingMediaURLs.count {
                pendingMediaCount = pendingMediaURLs.count
            }
        }
        guard !isBusy, !pendingMediaURLs.isEmpty else { return }
        let url = pendingMediaURLs.removeFirst()
        let settingsSnapshot = settings
        if settingsSnapshot.transcriptionEngine == .scribe,
           scribeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = strings.fillScribeKey
            isInspectorPresented = true
            pendingMediaURLs.insert(url, at: 0)
            return
        }
        if settingsSnapshot.transcriptionEngine == .typhoon, !TyphoonTranscriber.isInstalled {
            errorMessage = strings.typhoonNotInstalled
            isInspectorPresented = true
            pendingMediaURLs.insert(url, at: 0)
            return
        }

        isTranscribing = true
        progress = TranslationProgress(phase: .parsing, message: strings.extractingAudio)
        let scribeKeySnapshot = scribeAPIKey
        transcriptionRunID += 1
        let runID = transcriptionRunID
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            await self?.performTranscription(
                mediaURL: url,
                settings: settingsSnapshot,
                scribeKey: scribeKeySnapshot,
                runID: runID
            )
        }
    }

    func installTyphoon() {
        guard !isInstallingTyphoon else { return }
        isInstallingTyphoon = true
        typhoonInstallStatus = strings.typhoonInstallPreparing
        typhoonInstallTask?.cancel()
        typhoonInstallTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await TyphoonInstaller.install { [weak self] status in
                    Task { @MainActor [weak self] in
                        self?.typhoonInstallStatus = status
                    }
                }
                self.typhoonInstallStatus = self.strings.typhoonInstallComplete
                self.startNextMediaIfPossible()
            } catch is CancellationError {
                self.typhoonInstallStatus = self.strings.stopped
            } catch {
                self.typhoonInstallStatus = self.strings.typhoonInstallFailed
                self.errorMessage = error.localizedDescription
            }
            self.isInstallingTyphoon = false
        }
    }

    private func performTranscription(
        mediaURL: URL,
        settings: TranslationSettings,
        scribeKey: String,
        runID: Int
    ) async {
        // Set true only when this transcription hands off to a translation run;
        // then the queue is advanced by that translation's completion instead of
        // here, so we never start the next file concurrently with a live
        // translation (which would cancel it).
        var chainedToTranslation = false
        defer {
            if runID == transcriptionRunID {
                isTranscribing = false
                transcriptionTask = nil
                if !chainedToTranslation {
                    startNextMediaIfPossible()
                }
            }
        }
        do {
            // WhisperKit is the only engine biased by the vocabulary prompt, so it
            // is the only one whose cache key depends on it.
            let vocabularyPrompt = settings.transcriptionEngine == .whisperKit
                ? Self.vocabularyPrompt(from: settings.translationMemory)
                : nil
            let cacheKey = TranscriptionCacheStore.Key(
                mediaURL: mediaURL,
                engine: settings.transcriptionEngine,
                model: settings.whisperModel,
                language: settings.transcriptionLanguage,
                vocabulary: vocabularyPrompt
            )

            let segments: [TranscribedSegment]
            if let cached = TranscriptionCacheStore.load(for: cacheKey) {
                segments = cached
                progress = TranslationProgress(phase: .parsing, message: strings.transcriptionCacheHit)
            } else {
                let audioURL = try await AudioExtractor.extractAudioIfNeeded(from: mediaURL)
                defer {
                    if audioURL != mediaURL {
                        try? FileManager.default.removeItem(at: audioURL)
                    }
                }
                try Task.checkCancellation()

                let transcriber: any SubtitleTranscriber
                switch settings.transcriptionEngine {
                case .scribe:
                    transcriber = ScribeTranscriber(apiKey: scribeKey)
                case .typhoon:
                    transcriber = TyphoonTranscriber()
                case .whisperKit:
                    transcriber = WhisperKitTranscriber(
                        model: settings.whisperModel,
                        vocabularyPrompt: vocabularyPrompt
                    )
                }

                progress = TranslationProgress(phase: .parsing, message: strings.preparingModel)
                // Normalize the "auto" sentinel here so engines only see nil (auto)
                // or a concrete ISO code, per the SubtitleTranscriber contract.
                let languageHint = settings.transcriptionLanguage == "auto"
                    ? nil
                    : settings.transcriptionLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
                segments = try await transcriber.transcribe(
                    audioURL: audioURL,
                    languageHint: languageHint?.isEmpty == true ? nil : languageHint
                ) { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self, self.isTranscribing, runID == self.transcriptionRunID else { return }
                        switch update {
                        case .preparingModel:
                            self.progress.message = self.strings.preparingModel
                        case let .downloadingModel(fraction):
                            self.progress.message = self.strings.downloadingModel(percent: Int(fraction * 100))
                        case .uploading:
                            self.progress.message = self.strings.uploadingAudio
                        case let .transcribing(fraction):
                            self.progress.message = self.strings.transcribing(percent: Int(fraction * 100))
                        }
                    }
                }
                TranscriptionCacheStore.save(segments, for: cacheKey)
            }
            try Task.checkCancellation()
            guard runID == transcriptionRunID else { return }

            let cues = SegmentCueBuilder.makeCues(from: segments)
            guard !cues.isEmpty else {
                progress = TranslationProgress(phase: .failed, message: strings.transcriptionEmpty)
                return
            }

            let fileSize = (try? mediaURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil
            let document = SubtitleDocument(
                name: mediaURL.deletingPathExtension().lastPathComponent,
                sourceURL: mediaURL,
                rawByteCount: fileSize ?? 0,
                targetLanguage: settings.targetLanguage,
                cues: cues
            )
            documents.insert(document, at: 0)
            selectedDocumentID = document.id
            validation = ValidationReport.make(cues: cues, threshold: settings.readingSpeedLimit)
            progress = TranslationProgress(phase: .idle, message: strings.transcribed(count: cues.count))

            // 一体化：识别完成后直接进入翻译流水线。必须先清掉转写状态，
            // 否则 canTranslate 因 isTranscribing 仍为 true 而永远不通过。
            isTranscribing = false
            if canTranslate {
                chainedToTranslation = true
                translateSelected()
            }
        } catch is CancellationError {
            if runID == transcriptionRunID {
                progress = TranslationProgress(phase: .cancelled, message: strings.stopped)
            }
        } catch {
            guard runID == transcriptionRunID else { return }
            progress = TranslationProgress(phase: .failed, message: strings.transcriptionFailed)
            errorMessage = error.localizedDescription
        }
    }

    func clearTranslations() {
        guard let index = selectedDocumentIndex else { return }
        guard !documents[index].isDeleted else { return }
        var cues = documents[index].cues
        for cueIndex in cues.indices {
            cues[cueIndex].translation = nil
        }
        documents[index].cues = cues
        documents[index].generatedURL = nil
        documents[index].reviewCueIDs = []
        documents[index].contextSummary = nil
        documents[index].contextSummaryLanguage = nil
        validation = ValidationReport.make(cues: documents[index].cues, threshold: settings.readingSpeedLimit)
        progress = TranslationProgress(phase: .idle, message: strings.translationsCleared)
    }

    /// Inline edit from the preview list: writes the new translation for one cue.
    /// Targets the document the row belonged to (not the current selection), so a
    /// commit that lands after the selection changed cannot write into another
    /// document. Registers with the window's UndoManager so Cmd+Z restores the
    /// previous translation (and Shift+Cmd+Z redoes) through the native chain.
    func updateTranslation(documentID: UUID, sequence: Int, text: String, undoManager: UndoManager? = nil) {
        guard let documentIndex = documents.firstIndex(where: { $0.id == documentID }) else { return }
        guard let cueIndex = documents[documentIndex].cues.firstIndex(where: { $0.sequence == sequence }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue = trimmed.isEmpty ? nil : trimmed
        let previous = documents[documentIndex].cues[cueIndex].translation
        guard previous != newValue else { return }
        documents[documentIndex].cues[cueIndex].translation = newValue
        // Protect this edit from an in-flight batch result for the same cue.
        if isTranslating {
            manualEditsDuringRun.insert(ManualEditKey(documentID: documentID, sequence: sequence))
        }
        if documents[documentIndex].id == selectedDocumentID {
            refreshValidation(for: documentID)
        }

        if let undoManager {
            undoManager.registerUndo(withTarget: self) { store in
                // Re-registering inside the undo handler makes redo work natively.
                MainActor.assumeIsolated {
                    store.updateTranslation(
                        documentID: documentID,
                        sequence: sequence,
                        text: previous ?? "",
                        undoManager: undoManager
                    )
                }
            }
            undoManager.setActionName(strings.editTranslation)
        }
    }

    /// Unprotected name candidates detected in one cue — drives the pin popover.
    func nameCandidates(forCueSequence sequence: Int) -> [String] {
        guard let documentIndex = selectedDocumentIndex,
              let cue = documents[documentIndex].cues.first(where: { $0.sequence == sequence })
        else {
            return []
        }
        let protectedNames = Set(
            settings.translationMemory.flatMap { [$0.source.normalizedNameKey, $0.target.normalizedNameKey] }
        )
        return cue.text.probableNameCandidates()
            .filter { !protectedNames.contains($0.normalizedNameKey) }
    }

    /// Pins user-confirmed name translations into translation memory. An empty
    /// target keeps the source spelling as-is. Clears the review warning on every
    /// cue whose candidates are now all covered.
    func pinNames(_ entries: [(source: String, target: String)], forCueSequence sequence: Int) {
        guard let documentIndex = selectedDocumentIndex else { return }

        // Batch the memory writes into one settings mutation so settings.didSet
        // (JSON-encodes + persists) fires once, not per name.
        var memory = settings.translationMemory
        var pinned: [String] = []
        for entry in entries {
            let source = entry.source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { continue }
            let trimmedTarget = entry.target.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = trimmedTarget.isEmpty ? source : trimmedTarget
            pinned.append(source)
            if let index = memory.firstIndex(where: { $0.source.caseInsensitiveCompare(source) == .orderedSame }) {
                memory[index].target = target
                memory[index].note = strings.keptNameNote
            } else {
                memory.append(TranslationMemoryEntry(source: source, target: target, note: strings.keptNameNote))
            }
        }
        guard !pinned.isEmpty else {
            documents[documentIndex].reviewCueIDs.remove(sequence)
            return
        }
        settings.translationMemory = memory
        markReviewWarnings(for: documents[documentIndex].id, settings: settings)
        // Do not stamp .idle over a live translation's phase-derived busy state.
        if !isBusy {
            progress = TranslationProgress(phase: .idle, message: strings.namesKept(pinned))
        }
    }

    /// Romanized proper nouns pinned in translation memory, fed to Whisper as a
    /// vocabulary hint so they are transcribed correctly.
    nonisolated static func vocabularyPrompt(from memory: [TranslationMemoryEntry]) -> String? {
        SpeechVocabulary.prompt(from: memory)
    }

    func checkForUpdates() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        guard let currentVersion, !currentVersion.isEmpty else { return }
        Task { [weak self] in
            guard let url = URL(string: "https://api.github.com/repos/SUDAcyber/SUDA-Subtitle-Assistant/releases/latest"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let release = try? JSONDecoder().decode(LatestRelease.self, from: data)
            else {
                return
            }
            let latest = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
            guard SemanticVersion.isNewer(latest, than: currentVersion) else { return }
            let dmgURL = release.assets?
                .first { $0.name.lowercased().hasSuffix(".dmg") }
                .flatMap { URL(string: $0.browserDownloadUrl) }
            await MainActor.run { [weak self] in
                self?.availableUpdateVersion = latest
                self?.availableUpdateURL = URL(string: release.htmlUrl)
                self?.availableUpdateDMG = dmgURL
            }
        }
    }

    /// Downloads the release DMG straight into ~/Downloads and reveals it, so the
    /// user skips the browser round-trip. Falls back to the release page when the
    /// release carries no DMG asset.
    func downloadUpdate() {
        guard !isDownloadingUpdate else { return }
        guard let dmgURL = availableUpdateDMG else {
            if let page = availableUpdateURL {
                NSWorkspace.shared.open(page)
            }
            return
        }
        isDownloadingUpdate = true
        Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in self?.isDownloadingUpdate = false }
            }
            do {
                let (tempURL, response) = try await URLSession.shared.download(from: dmgURL)
                guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
                    throw URLError(.badServerResponse)
                }
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                var destination = downloads.appendingPathComponent(dmgURL.lastPathComponent)
                var attempt = 2
                while FileManager.default.fileExists(atPath: destination.path) {
                    let base = dmgURL.deletingPathExtension().lastPathComponent
                    destination = downloads.appendingPathComponent("\(base)-\(attempt).dmg")
                    attempt += 1
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                    NSWorkspace.shared.open(destination)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.errorMessage = self.strings.updateDownloadFailed(error.localizedDescription)
                    if let page = self.availableUpdateURL {
                        NSWorkspace.shared.open(page)
                    }
                }
            }
        }
    }

    private struct LatestRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }

        let tagName: String
        let htmlUrl: String
        let assets: [Asset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case assets
        }
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
        validation = ValidationReport.make(cues: documents[index].cues, threshold: settings.readingSpeedLimit)
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

    func locateNextTranslationMatch() {
        guard let document = selectedDocument else {
            errorMessage = strings.importFileFirst
            return
        }
        let needle = replacementSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            errorMessage = strings.enterSearchText
            return
        }
        let options: String.CompareOptions = replacementMatchCase ? [] : [.caseInsensitive]
        let matches = document.cues.filter { cue in
            cue.translation?.range(of: needle, options: options) != nil
        }
        guard !matches.isEmpty else {
            replacementLocatedCueSequence = nil
            errorMessage = strings.noTranslationMatch
            return
        }

        let next = matches.first { cue in
            guard let current = replacementLocatedCueSequence else { return true }
            return cue.sequence > current
        } ?? matches[0]
        showReviewCuesOnly = false
        showFastCuesOnly = false
        replacementLocatedCueSequence = next.sequence
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
        var cues = documents[documentIndex].cues
        for cueIndex in cues.indices {
            guard let translation = cues[cueIndex].translation else {
                continue
            }
            let count = translation.matchCount(of: needle, matchCase: replacementMatchCase)
            guard count > 0 else { continue }
            cues[cueIndex].translation = translation.replacingAllOccurrences(
                of: needle,
                with: replacementText,
                matchCase: replacementMatchCase
            )
            replacements += count
        }
        if replacements > 0 {
            documents[documentIndex].cues = cues
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
            let text = SRTParser.render(document.cues, layout: settings.exportLayout)
            try text.write(to: url, atomically: true, encoding: .utf8)
            if let index = selectedDocumentIndex {
                documents[index].generatedURL = url
            }
            progress = TranslationProgress(phase: .finished, message: strings.exported)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportSourceSubtitleWithPanel() {
        guard let document = selectedDocument, !document.isDeleted else {
            errorMessage = strings.noExportableSubtitle
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.srtSubtitle]
        panel.nameFieldStringValue = "\(document.name)-\(strings.sourceSubtitleFilenameSuffix).srt"
        panel.prompt = strings.export

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = SRTParser.render(document.cues, preferTranslations: false)
            try text.write(to: url, atomically: true, encoding: .utf8)
            progress = TranslationProgress(phase: .finished, message: strings.sourceSubtitleExported)
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
        apiKey: String,
        runID: Int
    ) async {
        defer {
            // Only the current run may clear the shared handle / advance the queue;
            // a cancelled older run unwinding later must not touch newer state.
            if runID == translationRunID {
                translationTask = nil
                startNextMediaIfPossible()
            }
        }
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
            // Re-runs (补翻) reuse the cached summary — but only if it was written
            // in the current target language, else the glossary would be in the
            // wrong language.
            let existing = documents.first(where: { $0.id == documentID })
            let cachedSummary = existing?.contextSummary
            let cacheLanguageMatches = existing?.contextSummaryLanguage == settings.targetLanguage
            if let cachedSummary, !cachedSummary.isEmpty, cacheLanguageMatches {
                batches = batches.map { $0.withContextSummary(cachedSummary) }
            } else {
                progress = TranslationProgress(
                    phase: .translating,
                    currentBatch: 0,
                    totalBatches: batches.count,
                    message: strings.analyzingContext
                )
                let sample = Self.analysisSample(from: sourceCues)
                if let summary = try? await client.analyzeContext(sourceText: sample, settings: settings, apiKey: apiKey) {
                    batches = batches.map { $0.withContextSummary(summary) }
                    if let index = documents.firstIndex(where: { $0.id == documentID }) {
                        documents[index].contextSummary = summary
                        documents[index].contextSummaryLanguage = settings.targetLanguage
                    }
                }
                if Task.isCancelled {
                    progress = TranslationProgress(phase: .cancelled, message: strings.stopped)
                    return
                }
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
        guard !translations.isEmpty,
              let documentIndex = documents.firstIndex(where: { $0.id == documentID }) else { return }
        // Mutate a local copy and assign once: per-cue subscript writes each fire
        // the documents didSet (history-save churn) and a linear index scan.
        var cues = documents[documentIndex].cues
        let indexBySequence = Dictionary(
            cues.enumerated().map { ($1.sequence, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var changed = false
        for (id, text) in translations {
            // Never overwrite a translation the user manually edited during this run.
            if manualEditsDuringRun.contains(ManualEditKey(documentID: documentID, sequence: id)) { continue }
            guard let cueIndex = indexBySequence[id] else { continue }
            cues[cueIndex].translation = text
            changed = true
        }
        if changed {
            documents[documentIndex].cues = cues
        }
    }

    private func refreshValidation(for documentID: UUID) {
        guard let document = documents.first(where: { $0.id == documentID }) else { return }
        validation = ValidationReport.make(cues: document.cues, threshold: settings.readingSpeedLimit)
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
        let text = SRTParser.render(documents[documentIndex].cues, layout: settings.exportLayout)
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
