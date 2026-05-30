import SwiftUI
import SubtitleForgeCore

struct WorkspaceView: View {
    @Bindable var store: AppStore

    var body: some View {
        ZStack {
            AppTheme.graphite.ignoresSafeArea()
            if let document = store.selectedDocument {
                VStack(spacing: 0) {
                    JobHeaderView(document: document, progress: store.progress, validation: store.validation)
                    Divider().overlay(AppTheme.graphitePanel)
                    SubtitlePreviewView(store: store, document: document)
                }
            } else {
                EmptyStateView(store: store)
            }
        }
    }
}

private struct JobHeaderView: View {
    let document: SubtitleDocument
    let progress: TranslationProgress
    let validation: ValidationReport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(document.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.ivory)
                        .lineLimit(1)
                    Text("\(document.cues.count) cues · \(document.targetLanguage)")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedIvory)
                }

                Spacer()

                StatusCapsule(title: "批次", value: batchText)
                StatusCapsule(title: "校验", value: validation.summary, accent: validation.isComplete ? AppTheme.success : AppTheme.brass)
                StatusCapsule(title: "进度", value: "\(Int(document.completionFraction * 100))%")
            }

            ProgressView(value: document.completionFraction)
                .tint(AppTheme.brass)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(AppTheme.graphiteRaised)
    }

    private var batchText: String {
        guard progress.totalBatches > 0 else { return "0/0" }
        return "\(progress.currentBatch)/\(progress.totalBatches)"
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
                    SubtitleCueRow(cue: cue)
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
                .fill(cue.hasTranslation ? AppTheme.graphiteRaised : AppTheme.graphitePanel.opacity(0.76))
        )
    }
}

private struct EmptyStateView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "captions.bubble.fill")
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
                Label("选择字幕文件", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.brass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(48)
    }
}
