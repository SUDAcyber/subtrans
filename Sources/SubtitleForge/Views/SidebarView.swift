import SwiftUI

struct SidebarView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "captions.bubble")
                    .foregroundStyle(AppTheme.brass)
                Text("Subtitle Forge")
                    .font(.headline.weight(.semibold))
                Spacer()
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
                Section("文件") {
                    ForEach(store.documents) { document in
                        DocumentRow(document: document)
                            .tag(document.id)
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
            Image(systemName: document.completionFraction >= 1 ? "checkmark.seal.fill" : "doc.text")
                .foregroundStyle(document.completionFraction >= 1 ? AppTheme.success : AppTheme.blueSlate)
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
}
