import SwiftUI

struct SidebarView: View {
    @Bindable var store: AppStore

    var body: some View {
        let strings = store.strings

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: AppIconSymbol.app)
                    .foregroundStyle(AppTheme.brass)
                Text(strings.projectManagement)
                    .font(.headline.weight(.semibold))
                Spacer()
                Button {
                    store.moveSelectedToTrash()
                } label: {
                    Image(systemName: AppIconSymbol.trash)
                }
                .buttonStyle(.borderless)
                .help(strings.moveToTrash)
                .disabled(store.selectedDocument?.isDeleted != false)

                Button {
                    store.importWithPanel()
                } label: {
                    Image(systemName: AppIconSymbol.quickAdd)
                }
                .buttonStyle(.borderless)
                .help(strings.importAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            List(selection: $store.selectedDocumentID) {
                if !store.mediaQueue.isEmpty {
                    Section {
                        ForEach(Array(store.mediaQueue.enumerated()), id: \.offset) { index, url in
                            QueuedMediaRow(
                                position: index + 1,
                                url: url,
                                strings: strings,
                                onRemove: { store.removeQueuedMedia(at: index) }
                            )
                        }
                    } header: {
                        HStack {
                            Text(strings.mediaQueueSection(store.mediaQueue.count))
                            Spacer()
                            if !store.isBusy {
                                Button(strings.resumeQueue) {
                                    store.resumeMediaQueue()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .foregroundStyle(AppTheme.brass)
                            }
                            Button(strings.clearQueue) {
                                store.clearMediaQueue()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(AppTheme.mutedIvory)
                        }
                    }
                }

                Section(strings.history) {
                    ForEach(store.activeDocuments) { document in
                        DocumentRow(document: document, strings: strings)
                            .tag(document.id)
                            .contextMenu {
                                Button(strings.moveToTrash, role: .destructive) {
                                    store.moveDocumentToTrash(id: document.id)
                                }
                            }
                    }
                }

                if !store.trashedDocuments.isEmpty {
                    Section(strings.trash) {
                        ForEach(store.trashedDocuments) { document in
                            TrashDocumentRow(document: document, store: store, strings: strings)
                                .tag(document.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: store.progress.fraction)
                    .tint(AppTheme.brass)
                HStack {
                    Text(store.progress.message)
                        .lineLimit(1)
                    Spacer()
                    Text(strings.validationSummary(store.validation))
                        .foregroundStyle(store.validation.isComplete ? AppTheme.success : AppTheme.mutedIvory)
                }
                .font(.caption)
                .foregroundStyle(AppTheme.mutedIvory)
            }
            .padding(14)
        }
    }
}

private struct QueuedMediaRow: View {
    let position: Int
    let url: URL
    let strings: AppStrings
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Text("\(position)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.mutedIvory)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                Text(url.pathExtension.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onRemove()
            } label: {
                Image(systemName: AppIconSymbol.remove)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.mutedIvory)
            .help(strings.removeFromQueue)
        }
        .padding(.vertical, 2)
    }
}

private struct DocumentRow: View {
    let document: SubtitleDocument
    let strings: AppStrings

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: documentIcon)
                .foregroundStyle(documentIconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(strings.cueCountWithSize(count: document.cues.count, size: document.displayByteSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var documentIcon: String {
        if document.hasReviewWarnings { return AppIconSymbol.reviewWarning }
        return document.completionFraction >= 1 ? AppIconSymbol.completed : AppIconSymbol.document
    }

    private var documentIconColor: Color {
        if document.hasReviewWarnings { return AppTheme.warning }
        return document.completionFraction >= 1 ? AppTheme.success : AppTheme.blueSlate
    }
}

private struct TrashDocumentRow: View {
    let document: SubtitleDocument
    @Bindable var store: AppStore
    let strings: AppStrings

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: AppIconSymbol.trash)
                .foregroundStyle(AppTheme.mutedIvory)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(strings.autoDelete15Days)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.restoreDocument(id: document.id)
            } label: {
                Image(systemName: AppIconSymbol.restore)
            }
            .buttonStyle(.borderless)
            .help(strings.restore)

            Button {
                store.permanentlyDeleteDocument(id: document.id)
            } label: {
                Image(systemName: AppIconSymbol.deleteForever)
            }
            .buttonStyle(.borderless)
            .help(strings.permanentlyDelete)
        }
        .padding(.vertical, 3)
    }
}
