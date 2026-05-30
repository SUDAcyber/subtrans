import SwiftUI
import SubtitleForgeCore

struct InspectorView: View {
    @Bindable var store: AppStore
    @State private var memorySource = ""
    @State private var memoryTarget = ""
    @State private var memoryNote = "专名"
    private let targetLanguages = ["简体中文", "繁体中文", "英文", "日文", "韩文", "西班牙文", "法文", "德文", "葡萄牙文", "俄文"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                providerSection
                modelSection
                chunkSection
                memorySection
                promptSection
                validationSection
            }
            .padding(18)
        }
        .background(AppTheme.graphiteRaised)
    }

    private var header: some View {
        HStack {
            Text("设置")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ivory)
            Spacer()
            Button {
                store.isInspectorPresented = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("关闭")
        }
    }

    private var providerSection: some View {
        SettingsGroup(title: "接口") {
            HStack {
                Button("AIHubMix") {
                    store.applyAIHubMixPreset()
                }
                Button("OpenAI") {
                    store.applyOpenAIPreset()
                }
            }
            .buttonStyle(.bordered)

            SettingsField(title: "接口名称") {
                TextField("接口名称", text: $store.settings.providerName)
            }

            SettingsField(title: "接口地址") {
                TextField("接口地址", text: $store.settings.baseURL)
                    .textContentType(.URL)
            }

            SettingsField(title: "密钥") {
                SecureField("密钥", text: $store.apiKey)
            }
        }
    }

    private var modelSection: some View {
        SettingsGroup(title: "模型") {
            SettingsField(title: "模型名称") {
                TextField("模型名称", text: $store.settings.model)
            }

            Picker("接口模式", selection: $store.settings.endpoint) {
                ForEach(TranslationEndpoint.allCases) { endpoint in
                    Text(endpoint.displayName).tag(endpoint)
                }
            }
            .pickerStyle(.segmented)

            Picker("目标语言", selection: $store.settings.targetLanguage) {
                ForEach(targetLanguages, id: \.self) {
                    Text($0).tag($0)
                }
            }

            TextField("自定义目标语言", text: $store.settings.targetLanguage)

            Picker("推理深度", selection: $store.settings.reasoningEffort) {
                ForEach(ReasoningEffort.allCases) { effort in
                    Text(effort.displayName).tag(effort)
                }
            }

            Picker("输出长度", selection: $store.settings.textVerbosity) {
                ForEach(TextVerbosity.allCases) { verbosity in
                    Text(verbosity.displayName).tag(verbosity)
                }
            }

            Toggle("移除目标标点", isOn: $store.settings.stripTargetPunctuation)
        }
    }

    private var chunkSection: some View {
        SettingsGroup(title: "分段") {
            NumericSettingRow(title: "每批条数", suffix: "条", value: $store.settings.chunkCueLimit, range: 1...500, step: 10)
            NumericSettingRow(title: "字符上限", suffix: "字", value: $store.settings.maxSourceCharacters, range: 500...50_000, step: 500)
            NumericSettingRow(title: "上下文", suffix: "条", value: $store.settings.contextOverlap, range: 0...50, step: 1)
            NumericSettingRow(title: "失败重试", suffix: "次", value: $store.settings.retryLimit, range: 0...10, step: 1)
            NumericSettingRow(title: "预览数量", suffix: "条", value: $store.previewCueLimit, range: 50...20_000, step: 100)
        }
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("后台记忆库", systemImage: "brain.head.profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.brass)
                Spacer()
                Text("\(store.settings.translationMemory.count) 条")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.mutedIvory)
            }

            SettingsField(title: "原文或名字") {
                TextField("例如 Ko Song 或 เซิร์ฟ", text: $memorySource)
            }

            SettingsField(title: "固定译法") {
                TextField("例如 Ko Song 或 Surf", text: $memoryTarget)
            }

            SettingsField(title: "备注") {
                TextField("例如 泰语人名", text: $memoryNote)
            }

            HStack {
                Button("加入记忆") {
                    store.addMemoryEntry(source: memorySource, target: memoryTarget, note: memoryNote)
                    memorySource = ""
                    memoryTarget = ""
                }

                Button("恢复预置") {
                    store.restoreDefaultMemoryEntries()
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.settings.translationMemory) { entry in
                        MemoryEntryRow(entry: entry) {
                            store.removeMemoryEntry(id: entry.id)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.graphitePanel.opacity(0.92))
        )
    }

    private var promptSection: some View {
        SettingsGroup(title: "翻译指令") {
            TextEditor(text: $store.settings.promptTemplate)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 210)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppTheme.graphite)
                )
        }
    }

    private var validationSection: some View {
        SettingsGroup(title: "校验") {
            LabeledContent("总条数", value: "\(store.validation.totalCues)")
            LabeledContent("已翻译", value: "\(store.validation.translatedCues)")
            LabeledContent("缺失", value: "\(store.validation.missingIDs.count)")
            LabeledContent("重复序号", value: "\(store.validation.duplicateIDs.count)")

            Button(role: .destructive) {
                store.clearTranslations()
            } label: {
                Label("清空译文", systemImage: "trash")
            }
            .disabled(store.selectedDocument == nil || store.isTranslating)
        }
    }
}

private struct MemoryEntryRow: View {
    let entry: TranslationMemoryEntry
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ivory)
                    .lineLimit(1)
                Text(entry.target)
                    .font(.caption)
                    .foregroundStyle(AppTheme.brass)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.mutedIvory)
                    .lineLimit(1)
            }

            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.mutedIvory)
            .help("移除")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(AppTheme.graphite)
        )
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.brass)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
    }
}

private struct SettingsField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.mutedIvory)
            content
        }
    }
}

private struct NumericSettingRow: View {
    let title: String
    let suffix: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(AppTheme.ivory)
                .frame(width: 76, alignment: .leading)

            TextField("", value: boundedValue, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 86)
                .onSubmit(clampValue)

            Text(suffix)
                .foregroundStyle(AppTheme.mutedIvory)
                .frame(width: 22, alignment: .leading)

            Spacer(minLength: 8)

            Stepper("", value: boundedValue, in: range, step: step)
                .labelsHidden()
                .frame(width: 54)
        }
        .onChange(of: value) { _, _ in
            clampValue()
        }
    }

    private var boundedValue: Binding<Int> {
        Binding(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
    }

    private func clampValue() {
        value = min(max(value, range.lowerBound), range.upperBound)
    }
}
