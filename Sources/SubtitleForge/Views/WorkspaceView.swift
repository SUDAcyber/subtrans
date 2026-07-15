import SwiftUI
import SubtitleForgeCore

struct WorkspaceView: View {
    @Bindable var store: AppStore

    var body: some View {
        ZStack {
            AppTheme.graphite.ignoresSafeArea()
            if let document = store.selectedDocument {
                VStack(spacing: 0) {
                    JobHeaderView(store: store, document: document)
                    if store.isFindReplacePresented {
                        FindReplaceToolbar(store: store)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Divider().overlay(AppTheme.divider)
                    SubtitlePreviewView(store: store, document: document)
                }
                .animation(.smooth(duration: 0.18), value: store.isFindReplacePresented)
            } else {
                EmptyStateView(store: store)
            }
        }
    }
}

private struct JobHeaderView: View {
    @Bindable var store: AppStore
    let document: SubtitleDocument

    var body: some View {
        let strings = store.strings

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(document.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.ivory)
                        .lineLimit(1)
                    Text("\(strings.cueCount(document.cues.count)) · \(strings.targetLanguageLabel(document.targetLanguage))")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedIvory)

                    if let generatedURL = document.generatedURL {
                        Label(strings.generated(generatedURL.lastPathComponent), systemImage: AppIconSymbol.completed)
                            .font(.caption)
                            .foregroundStyle(AppTheme.success)
                            .lineLimit(1)
                    }
                    if document.hasReviewWarnings {
                        Button {
                            store.showReviewCuesOnly.toggle()
                        } label: {
                            Label(
                                store.showReviewCuesOnly
                                    ? strings.showingReviewOnly(document.reviewCueIDs.count)
                                    : strings.reviewWarnings(document.reviewCueIDs.count),
                                systemImage: AppIconSymbol.reviewWarning
                            )
                            .font(.caption.weight(.medium))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.warning)
                        .help(strings.toggleReviewFilter)
                    }
                    if !store.validation.fastCueIDs.isEmpty || store.showFastCuesOnly {
                        Button {
                            store.showFastCuesOnly.toggle()
                        } label: {
                            Label(
                                store.showFastCuesOnly
                                    ? strings.showingFastOnly(store.validation.fastCueIDs.count)
                                    : strings.fastWarnings(store.validation.fastCueIDs.count),
                                systemImage: AppIconSymbol.readingSpeed
                            )
                            .font(.caption.weight(.medium))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.blueSlate)
                        .help(strings.toggleFastFilter)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                actionButtons
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(store.progress.message)
                        .lineLimit(1)
                    if store.pendingMediaCount > 0 {
                        Text(strings.queuedFiles(store.pendingMediaCount))
                            .foregroundStyle(AppTheme.brass)
                    }
                    Spacer()
                    Text(progressDetailText)
                        .foregroundStyle(store.validation.isComplete ? AppTheme.success : AppTheme.mutedIvory)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.mutedIvory)

                ProgressView(value: document.completionFraction)
                    .tint(AppTheme.brass)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(AppTheme.graphiteRaised)
    }

    private var actionButtons: some View {
        let strings = store.strings

        return HStack(spacing: 10) {
            if store.isBusy {
                Button {
                    store.cancelTranslation()
                } label: {
                    Label(strings.stopTask, systemImage: AppIconSymbol.stop)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.warning)
            } else {
                Button {
                    store.translateSelected()
                } label: {
                    Label(strings.startTranslation, systemImage: AppIconSymbol.translate)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brass)
                .disabled(!store.canTranslate)
            }

            Button {
                store.exportSourceSubtitleWithPanel()
            } label: {
                Label(strings.exportSourceSubtitle, systemImage: AppIconSymbol.document)
            }
            .buttonStyle(.bordered)
            .disabled(document.cues.isEmpty || document.isDeleted)

            Button {
                store.exportSelectedToSourceFolder()
            } label: {
                Label(strings.generateSubtitle, systemImage: AppIconSymbol.generate)
            }
            .buttonStyle(.bordered)
            .disabled(document.translatedCount == 0 || document.isDeleted)

            Button {
                store.exportSelectedWithPanel()
            } label: {
                Label(strings.saveAs, systemImage: AppIconSymbol.export)
            }
            .buttonStyle(.bordered)
            .disabled(document.translatedCount == 0 || document.isDeleted)
        }
        .controlSize(.large)
        .fixedSize()
    }

    private var progressDetailText: String {
        let strings = store.strings
        let percent = "\(Int(document.completionFraction * 100))%"
        if store.isTranslating, store.progress.totalBatches > 0 {
            return "\(strings.batch) \(store.progress.currentBatch)/\(store.progress.totalBatches) · \(percent)"
        }
        return "\(strings.validationSummary(store.validation)) · \(percent)"
    }
}

private struct FindReplaceToolbar: View {
    @Bindable var store: AppStore

    var body: some View {
        let strings = store.strings
        // Hoisted: each read walks every cue translation, so read it once per render.
        let matchCount = store.replacementMatchCount

        ViewThatFits(in: .horizontal) {
            horizontalLayout(strings: strings, matchCount: matchCount)
            compactLayout(strings: strings, matchCount: matchCount)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 12)
        .background(AppTheme.graphiteRaised.opacity(0.76))
    }

    private func horizontalLayout(strings: AppStrings, matchCount: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: AppIconSymbol.search)
                .foregroundStyle(AppTheme.mutedIvory)

            TextField(strings.searchTranslation, text: $store.replacementSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160)

            TextField(strings.replaceWith, text: $store.replacementText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160)

            Toggle(strings.matchCase, isOn: $store.replacementMatchCase)
                .toggleStyle(.checkbox)

            Text(strings.matchCount(matchCount))
                .font(.caption.weight(.semibold))
                .foregroundStyle(matchCount > 0 ? AppTheme.brass : AppTheme.mutedIvory)
                .frame(width: 48, alignment: .trailing)

            Button(strings.locateNextMatch) {
                store.locateNextTranslationMatch()
            }
            .disabled(matchCount == 0)

            Button(strings.replaceOne) {
                store.replaceOneTranslationMatch()
            }
            .disabled(store.selectedDocument == nil || store.replacementSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(strings.replaceAll) {
                store.replaceAllTranslationMatches()
            }
            .disabled(store.selectedDocument == nil || matchCount == 0)
        }
    }

    private func compactLayout(strings: AppStrings, matchCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(strings.findReplaceTranslation, systemImage: AppIconSymbol.replace)
                    .foregroundStyle(AppTheme.mutedIvory)
                Spacer()
                Text(strings.matchCount(matchCount))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(matchCount > 0 ? AppTheme.brass : AppTheme.mutedIvory)
            }

            HStack(spacing: 10) {
                TextField(strings.searchTranslation, text: $store.replacementSearchText)
                    .textFieldStyle(.roundedBorder)
                TextField(strings.replaceWith, text: $store.replacementText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 10) {
                Toggle(strings.matchCase, isOn: $store.replacementMatchCase)
                    .toggleStyle(.checkbox)

                Spacer()

                Button(strings.locateNextMatch) {
                    store.locateNextTranslationMatch()
                }
                .disabled(matchCount == 0)

                Button(strings.replaceOne) {
                    store.replaceOneTranslationMatch()
                }
                .disabled(store.selectedDocument == nil || store.replacementSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(strings.replaceAll) {
                    store.replaceAllTranslationMatches()
                }
                .disabled(store.selectedDocument == nil || matchCount == 0)
            }
        }
    }
}

private struct SubtitlePreviewView: View {
    @Bindable var store: AppStore
    let document: SubtitleDocument
    @Environment(\.undoManager) private var undoManager

    private var isFiltering: Bool {
        (store.showReviewCuesOnly && document.hasReviewWarnings) || store.showFastCuesOnly
    }

    private var visibleCues: [SubtitleCue] {
        if store.showFastCuesOnly {
            let limit = store.settings.readingSpeedLimit
            return document.cues.filter { ($0.translationCPS ?? 0) > limit }
        }
        if store.showReviewCuesOnly, document.hasReviewWarnings {
            return document.cues.filter { document.reviewCueIDs.contains($0.sequence) }
        }
        let locatedIndex = store.replacementLocatedCueSequence.flatMap { sequence in
            document.cues.firstIndex { $0.sequence == sequence }
        }
        let limit = max(store.previewCueLimit, locatedIndex.map { $0 + 1 } ?? 0)
        return Array(document.cues.prefix(limit))
    }

    var body: some View {
        // Computed once per render (each evaluation walks/filters the cue list).
        let cues = visibleCues
        return ScrollViewReader { proxy in
            ScrollView {
                // Identity tied to the document so per-row @State (open inline
                // editors, drafts) is discarded when the selection switches.
                LazyVStack(spacing: 1) {
                    HeaderRow(strings: store.strings)
                    ForEach(cues) { cue in
                        SubtitleCueRow(
                            cue: cue,
                            needsReview: document.reviewCueIDs.contains(cue.sequence),
                            isLocated: store.replacementLocatedCueSequence == cue.sequence,
                            readingSpeedLimit: store.settings.readingSpeedLimit,
                            strings: store.strings,
                            nameCandidates: { store.nameCandidates(forCueSequence: cue.sequence) },
                            onPinNames: { store.pinNames($0, forCueSequence: cue.sequence) },
                            onEditTranslation: { store.updateTranslation(documentID: document.id, sequence: cue.sequence, text: $0, undoManager: undoManager) }
                        )
                        .id(cue.sequence)
                    }
                    if isFiltering, cues.isEmpty {
                        Text(store.strings.filterEmpty)
                            .font(.callout)
                            .foregroundStyle(AppTheme.mutedIvory)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                    }
                    if !isFiltering, document.cues.count > cues.count {
                        Text(store.strings.previewLimited(limit: store.previewCueLimit, total: document.cues.count))
                            .font(.caption)
                            .foregroundStyle(AppTheme.mutedIvory)
                            .padding(.vertical, 18)
                    }
                }
                .padding(18)
                .id(document.id)
            }
            .onChange(of: store.replacementLocatedCueSequence) { _, sequence in
                guard let sequence else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(sequence, anchor: .center)
                }
            }
        }
    }
}

private struct HeaderRow: View {
    let strings: AppStrings

    var body: some View {
        HStack(spacing: 14) {
            Text(strings.idTimeline)
                .frame(width: 168, alignment: .leading)
            Text(strings.source)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(strings.translation)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.mutedIvory)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct SubtitleCueRow: View {
    let cue: SubtitleCue
    let needsReview: Bool
    let isLocated: Bool
    let readingSpeedLimit: Double
    let strings: AppStrings
    let nameCandidates: () -> [String]
    let onPinNames: ([(source: String, target: String)]) -> Void
    let onEditTranslation: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isNamePopoverPresented = false
    @FocusState private var editorFocused: Bool

    private var isFast: Bool {
        (cue.translationCPS ?? 0) > readingSpeedLimit
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("#\(cue.sequence)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.ivory)
                Text(cue.timecode)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppTheme.mutedIvory)
                    .textSelection(.enabled)
                if isFast {
                    Label(strings.tooFast, systemImage: AppIconSymbol.readingSpeed)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.blueSlate)
                        .help(strings.tooFastHelp)
                }
                if needsReview {
                    Label(strings.reviewName, systemImage: AppIconSymbol.reviewWarning)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.warning)
                    Button {
                        isNamePopoverPresented = true
                    } label: {
                        Label(strings.keepNames, systemImage: AppIconSymbol.memory)
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.brass)
                    .help(strings.keepNamesHelp)
                    .popover(isPresented: $isNamePopoverPresented, arrowEdge: .trailing) {
                        NamePinPopover(
                            candidates: nameCandidates(),
                            strings: strings,
                            onConfirm: { entries in
                                onPinNames(entries)
                            }
                        )
                    }
                }
            }
            .frame(width: 168, alignment: .leading)

            Text(cue.text)
                .font(.body)
                .foregroundStyle(AppTheme.ivory)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            translationColumn
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(rowStroke, lineWidth: isLocated ? 2 : 1)
        )
    }

    @ViewBuilder
    private var translationColumn: some View {
        if isEditing {
            TextField(strings.pendingTranslation, text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .focused($editorFocused)
                .onSubmit(commitEdit)
                .onExitCommand {
                    isEditing = false
                }
                .onChange(of: editorFocused) { _, focused in
                    if !focused, isEditing {
                        commitEdit()
                    }
                }
        } else {
            // The translation Text keeps .textSelection for copy, but selectable
            // text swallows clicks on macOS, so editing is driven by an explicit
            // pencil button and a context-menu entry rather than a tap gesture.
            HStack(alignment: .top, spacing: 6) {
                Text(cue.translation?.isEmpty == false ? cue.translation ?? "" : strings.pendingTranslation)
                    .font(.body)
                    .foregroundStyle(cue.hasTranslation ? AppTheme.ivory : AppTheme.blueSlate)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    beginEdit()
                } label: {
                    Image(systemName: AppIconSymbol.edit)
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.mutedIvory)
                .help(strings.editTranslation)
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button(strings.editTranslation, systemImage: AppIconSymbol.edit) {
                    beginEdit()
                }
            }
        }
    }

    private func beginEdit() {
        draft = cue.translation ?? ""
        isEditing = true
        editorFocused = true
    }

    private func commitEdit() {
        guard isEditing else { return }
        isEditing = false
        onEditTranslation(draft)
    }

    private var rowBackground: Color {
        if isLocated {
            return AppTheme.brass.opacity(0.2)
        }
        if needsReview {
            return AppTheme.warning.opacity(0.14)
        }
        return cue.hasTranslation ? AppTheme.graphiteRaised : AppTheme.graphitePanel.opacity(0.76)
    }

    private var rowStroke: Color {
        if isLocated { return AppTheme.brass }
        if needsReview { return AppTheme.warning.opacity(0.65) }
        return .clear
    }
}

/// Per-name confirmation bubble for pinning detected names into memory: each
/// candidate shows an editable target (empty = keep the source spelling).
private struct NamePinPopover: View {
    let candidates: [String]
    let strings: AppStrings
    let onConfirm: ([(source: String, target: String)]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var targets: [String]

    init(candidates: [String], strings: AppStrings, onConfirm: @escaping ([(source: String, target: String)]) -> Void) {
        self.candidates = candidates
        self.strings = strings
        self.onConfirm = onConfirm
        _targets = State(initialValue: candidates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(strings.pinNamesTitle)
                .font(.headline)

            if candidates.isEmpty {
                Text(strings.pinNamesEmpty)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(candidates.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Text(candidates[index])
                            .font(.callout.weight(.medium))
                            .frame(minWidth: 70, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField(strings.pinNameFieldPlaceholder, text: $targets[index])
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                    }
                }

                Text(strings.pinNamesHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(strings.cancel) {
                    dismiss()
                }
                if !candidates.isEmpty {
                    Button(strings.pinNamesConfirm) {
                        onConfirm(Array(zip(candidates, targets)).map { (source: $0.0, target: $0.1) })
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 300)
    }
}

private struct EmptyStateView: View {
    @Bindable var store: AppStore

    var body: some View {
        let strings = store.strings

        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: AppIconSymbol.emptyState)
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.brass)
            VStack(alignment: .leading, spacing: 8) {
                Text(strings.emptyTitle)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(AppTheme.ivory)
                Text(strings.emptySubtitle)
                    .font(.title3)
                    .foregroundStyle(AppTheme.mutedIvory)
                Text(strings.transcriptionHint)
                    .font(.callout)
                    .foregroundStyle(AppTheme.mutedIvory)
            }
            Button {
                store.importWithPanel()
            } label: {
                Label(strings.chooseSubtitleFile, systemImage: AppIconSymbol.importFile)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.brass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(48)
    }
}
