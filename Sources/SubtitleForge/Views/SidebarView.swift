import SwiftUI

struct SidebarView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "captions.bubble")
                    .foregroundStyle(AppTheme.brass)
                Text("字幕锻造")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button {
                    store.moveSelectedToTrash()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("移到回收箱")
                .disabled(store.selectedDocument?.isDeleted != false)

                Button {
                    store.importWithPanel()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("导入")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            List(selection: $store.selectedDocumentID) {
                Section("历史记录") {
                    ForEach(store.activeDocuments) { document in
                        DocumentRow(document: document)
                            .tag(document.id)
                            .contextMenu {
                                Button("移到回收箱", role: .destructive) {
                                    store.moveDocumentToTrash(id: document.id)
                                }
                            }
                    }
                }

                if !store.trashedDocuments.isEmpty {
                    Section("回收箱") {
                        ForEach(store.trashedDocuments) { document in
                            TrashDocumentRow(document: document, store: store)
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
                    Text(store.validation.summary)
                        .foregroundStyle(store.validation.isComplete ? AppTheme.success : AppTheme.mutedIvory)
                }
                .font(.caption)
                .foregroundStyle(AppTheme.mutedIvory)
            }
            .padding(14)
        }
    }
}

private struct DocumentRow: View {
    let document: SubtitleDocument

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: documentIcon)
                .foregroundStyle(documentIconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("\(document.cues.count) 条 · \(document.displayByteSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var documentIcon: String {
        if document.hasReviewWarnings { return "exclamationmark.triangle.fill" }
        return document.completionFraction >= 1 ? "checkmark.seal.fill" : "doc.text"
    }

    private var documentIconColor: Color {
        if document.hasReviewWarnings { return AppTheme.warning }
        return document.completionFraction >= 1 ? AppTheme.success : AppTheme.blueSlate
    }
}

private struct TrashDocumentRow: View {
    let document: SubtitleDocument
    @Bindable var store: AppStore

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "trash")
                .foregroundStyle(AppTheme.mutedIvory)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("15 天后自动删除")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.restoreDocument(id: document.id)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("恢复")

            Button {
                store.permanentlyDeleteDocument(id: document.id)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("永久删除")
        }
        .padding(.vertical, 3)
    }
}
