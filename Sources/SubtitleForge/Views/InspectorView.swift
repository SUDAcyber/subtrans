import SwiftUI
import SubtitleForgeCore

struct InspectorView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                providerSection
                modelSection
                chunkSection
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

            TextField("Provider", text: $store.settings.providerName)
            TextField("Base URL", text: $store.settings.baseURL)
                .textContentType(.URL)
            SecureField("API Key", text: $store.apiKey)
                .onChange(of: store.apiKey) { _, _ in
                    store.saveAPIKey()
                }
        }
    }

    private var modelSection: some View {
        SettingsGroup(title: "模型") {
            TextField("Model", text: $store.settings.model)

            Picker("接口模式", selection: $store.settings.endpoint) {
                ForEach(TranslationEndpoint.allCases) { endpoint in
                    Text(endpoint.displayName).tag(endpoint)
                }
            }
            .pickerStyle(.segmented)

            Picker("目标语言", selection: $store.settings.targetLanguage) {
                ForEach(["简体中文", "繁體中文", "English", "日本語", "한국어", "Español", "Français", "Deutsch", "Português", "Русский"], id: \.self) {
                    Text($0).tag($0)
                }
            }

            TextField("自定义目标语言", text: $store.settings.targetLanguage)

            HStack {
                Text("Temperature")
                Slider(value: $store.settings.temperature, in: 0...1, step: 0.1)
                Text(store.settings.temperature, format: .number.precision(.fractionLength(1)))
                    .frame(width: 32, alignment: .trailing)
            }

            Picker("Reasoning", selection: $store.settings.reasoningEffort) {
                ForEach(ReasoningEffort.allCases) { effort in
                    Text(effort.rawValue).tag(effort)
                }
            }

            Picker("Verbosity", selection: $store.settings.textVerbosity) {
                ForEach(TextVerbosity.allCases) { verbosity in
                    Text(verbosity.rawValue).tag(verbosity)
                }
            }

            Toggle("移除目标标点", isOn: $store.settings.stripTargetPunctuation)
        }
    }

    private var chunkSection: some View {
        SettingsGroup(title: "分段") {
            Stepper("每批 \(store.settings.chunkCueLimit) 条", value: $store.settings.chunkCueLimit, in: 10...220, step: 10)
            Stepper("字符上限 \(store.settings.maxSourceCharacters)", value: $store.settings.maxSourceCharacters, in: 1_500...20_000, step: 500)
            Stepper("上下文 \(store.settings.contextOverlap) 条", value: $store.settings.contextOverlap, in: 0...20, step: 1)
            Stepper("失败重试 \(store.settings.retryLimit) 次", value: $store.settings.retryLimit, in: 0...5, step: 1)
            Stepper("预览 \(store.previewCueLimit) 条", value: $store.previewCueLimit, in: 100...5_000, step: 100)
        }
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
