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
                    FindReplaceToolbar(store: store)
                    Divider().overlay(AppTheme.divider)
                    SubtitlePreviewView(store: store, document: document)
                }
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(document.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.ivory)
                        .lineLimit(1)
                    Text("\(document.cues.count) 条 · \(document.targetLanguage)")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedIvory)

                    if let generatedURL = document.generatedURL {
                        Label("已生成 \(generatedURL.lastPathComponent)", systemImage: AppIconSymbol.completed)
                            .font(.caption)
                            .foregroundStyle(AppTheme.success)
                            .lineLimit(1)
                    }
                    if document.hasReviewWarnings {
                        Label("有 \(document.reviewCueIDs.count) 条疑似人名需要检查", systemImage: AppIconSymbol.reviewWarning)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                actionButtons
            }

            HStack(alignment: .center, spacing: 12) {
                StatusCapsule(title: "批次", value: batchText)
                StatusCapsule(title: "校验", value: store.validation.summary, accent: store.validation.isComplete ? AppTheme.success : AppTheme.brass)
                StatusCapsule(title: "进度", value: "\(Int(document.completionFraction * 100))%")

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("任务进度")
                        Spacer()
                        Text(store.progress.message)
                            .lineLimit(1)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.mutedIvory)

                    ProgressView(value: document.completionFraction)
                        .tint(AppTheme.brass)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(AppTheme.graphiteRaised)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            if store.isTranslating {
                Button {
                    store.cancelTranslation()
                } label: {
                    Label("停止任务", systemImage: AppIconSymbol.stop)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.warning)
            } else {
                Button {
                    store.translateSelected()
                } label: {
                    Label("开始任务", systemImage: AppIconSymbol.translate)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.brass)
                .disabled(!store.canTranslate)
            }

            Button {
                store.exportSelectedToSourceFolder()
            } label: {
                Label("生成字幕", systemImage: AppIconSymbol.generate)
            }
            .buttonStyle(.bordered)
            .disabled(document.translatedCount == 0 || document.isDeleted)

            Button {
                store.exportSelectedWithPanel()
            } label: {
                Label("另存为", systemImage: AppIconSymbol.export)
            }
            .buttonStyle(.bordered)
            .disabled(document.translatedCount == 0 || document.isDeleted)
        }
        .controlSize(.large)
        .fixedSize()
    }

    private var batchText: String {
        guard store.progress.totalBatches > 0 else { return "0/0" }
        return "\(store.progress.currentBatch)/\(store.progress.totalBatches)"
    }
}

private struct FindReplaceToolbar: View {
    @Bindable var store: AppStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            compactLayout
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 12)
        .background(AppTheme.graphiteRaised.opacity(0.76))
    }

    private var horizontalLayout: some View {
        HStack(spacing: 10) {
            Image(systemName: AppIconSymbol.search)
                .foregroundStyle(AppTheme.mutedIvory)

            TextField("查找译文", text: $store.replacementSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160)

            TextField("替换为", text: $store.replacementText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160)

            Toggle("区分大小写", isOn: $store.replacementMatchCase)
                .toggleStyle(.checkbox)

            Text("\(store.replacementMatchCount) 处")
                .font(.caption.weight(.semibold))
                .foregroundStyle(store.replacementMatchCount > 0 ? AppTheme.brass : AppTheme.mutedIvory)
                .frame(width: 48, alignment: .trailing)

            Button("替换一个") {
                store.replaceOneTranslationMatch()
            }
            .disabled(store.selectedDocument == nil || store.replacementSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("全部替换") {
                store.replaceAllTranslationMatches()
            }
            .disabled(store.selectedDocument == nil || store.replacementMatchCount == 0)
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("查找替换译文", systemImage: AppIconSymbol.replace)
                    .foregroundStyle(AppTheme.mutedIvory)
                Spacer()
                Text("\(store.replacementMatchCount) 处")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(store.replacementMatchCount > 0 ? AppTheme.brass : AppTheme.mutedIvory)
            }

            HStack(spacing: 10) {
                TextField("查找译文", text: $store.replacementSearchText)
                    .textFieldStyle(.roundedBorder)
                TextField("替换为", text: $store.replacementText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 10) {
                Toggle("区分大小写", isOn: $store.replacementMatchCase)
                    .toggleStyle(.checkbox)

                Spacer()

                Button("替换一个") {
                    store.replaceOneTranslationMatch()
                }
                .disabled(store.selectedDocument == nil || store.replacementSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("全部替换") {
                    store.replaceAllTranslationMatches()
                }
                .disabled(store.selectedDocument == nil || store.replacementMatchCount == 0)
            }
        }
    }
}

private struct StatusCapsule: View {
    let title: String
    let value: String
    var accent: Color = AppTheme.blueSlate

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.mutedIvory)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 11)
        .frame(minWidth: 86, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppTheme.graphitePanel)
        )
    }
}

private struct SubtitlePreviewView: View {
    @Bindable var store: AppStore
    let document: SubtitleDocument

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                HeaderRow()
                ForEach(Array(document.cues.prefix(store.previewCueLimit))) { cue in
                    SubtitleCueRow(cue: cue, needsReview: document.reviewCueIDs.contains(cue.sequence))
                }
                if document.cues.count > store.previewCueLimit {
                    Text("已为界面性能限制预览前 \(store.previewCueLimit) 条 导出仍包含全部 \(document.cues.count) 条")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedIvory)
                        .padding(.vertical, 18)
                }
            }
            .padding(18)
        }
    }
}

private struct HeaderRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Text("ID / 时间轴")
                .frame(width: 168, alignment: .leading)
            Text("原文")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("译文")
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
                if needsReview {
                    Label("检查人名", systemImage: AppIconSymbol.reviewWarning)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.warning)
                }
            }
            .frame(width: 168, alignment: .leading)

            Text(cue.text)
                .font(.body)
                .foregroundStyle(AppTheme.ivory)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(cue.translation?.isEmpty == false ? cue.translation ?? "" : "待翻译")
                .font(.body)
                .foregroundStyle(cue.hasTranslation ? AppTheme.ivory : AppTheme.blueSlate)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(needsReview ? AppTheme.warning.opacity(0.65) : .clear, lineWidth: 1)
        )
    }

    private var rowBackground: Color {
        if needsReview {
            return AppTheme.warning.opacity(0.14)
        }
        return cue.hasTranslation ? AppTheme.graphiteRaised : AppTheme.graphitePanel.opacity(0.76)
    }
}

private struct EmptyStateView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: AppIconSymbol.emptyState)
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.brass)
            VStack(alignment: .leading, spacing: 8) {
                Text("导入 SRT")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(AppTheme.ivory)
                Text("本地锁定序号和时间轴 分批翻译后再重建字幕")
                    .font(.title3)
                    .foregroundStyle(AppTheme.mutedIvory)
            }
            Button {
                store.importWithPanel()
            } label: {
                Label("选择字幕文件", systemImage: AppIconSymbol.importFile)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.brass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(48)
    }
}
