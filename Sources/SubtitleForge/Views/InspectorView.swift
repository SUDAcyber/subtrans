import SwiftUI
import SubtitleForgeCore

struct InspectorView: View {
    @Bindable var store: AppStore
    @State private var memorySource = ""
    @State private var memoryTarget = ""
    @State private var memoryNote = ""
    @State private var selectedTab: InspectorTab = .model

    var body: some View {
        let strings = store.strings

        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)

            InspectorTabBar(selection: $selectedTab, strings: strings)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

            Divider()
                .overlay(AppTheme.divider)

            tabContent
        }
        .background(AppTheme.graphiteRaised)
    }

    private var header: some View {
        let strings = store.strings

        return HStack {
            Text(strings.settings)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ivory)
            Spacer()
            Button {
                store.isInspectorPresented = false
            } label: {
                Image(systemName: AppIconSymbol.close)
            }
            .buttonStyle(.borderless)
            .help(strings.close)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .model:
            tabScroll {
                providerSection
                modelSection
                advancedSection
            }
        case .transcription:
            tabScroll {
                transcriptionSection
            }
        case .memory:
            tabScroll {
                memorySection
            }
        case .quality:
            tabScroll {
                promptSection
                validationSection
            }
        }
    }

    private func tabScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .padding(18)
        }
    }

    private var providerSection: some View {
        let strings = store.strings

        return SettingsGroup(title: strings.provider) {
            HStack {
                Button("AIHubMix") {
                    store.applyAIHubMixPreset()
                }
                Button("OpenAI") {
                    store.applyOpenAIPreset()
                }
            }
            .buttonStyle(.bordered)

            SettingsField(title: strings.providerName) {
                TextField(strings.providerName, text: $store.settings.providerName)
            }

            SettingsField(title: strings.providerURL) {
                TextField(strings.providerURL, text: $store.settings.baseURL)
                    .textContentType(.URL)
            }

            SettingsField(title: strings.apiKey) {
                SecureField(strings.apiKey, text: $store.apiKey)
            }
        }
    }

    private var modelSection: some View {
        let strings = store.strings

        return SettingsGroup(title: strings.model) {
            SettingsField(title: strings.modelName) {
                TextField(strings.modelName, text: $store.settings.model)
            }

            HStack(spacing: 6) {
                ForEach(["gpt-5.6-luna", "gpt-5.5"], id: \.self) { model in
                    Button(model) {
                        store.settings.model = model
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if store.settings.model.lowercased().hasPrefix("gpt-5.6-luna"),
               store.settings.endpoint == .chatCompletions {
                Text(strings.lunaChatHint)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedIvory)
            }

            Picker(strings.endpointMode, selection: $store.settings.endpoint) {
                ForEach(TranslationEndpoint.allCases) { endpoint in
                    Text(strings.endpointName(endpoint)).tag(endpoint)
                }
            }
            .pickerStyle(.segmented)

            Picker(strings.targetLanguage, selection: $store.settings.targetLanguage) {
                ForEach(strings.targetLanguageOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }

            TextField(strings.customTargetLanguage, text: targetLanguageText(strings: strings))

            Picker(strings.reasoningEffort, selection: $store.settings.reasoningEffort) {
                ForEach(ReasoningEffort.allCases) { effort in
                    Text(strings.reasoningName(effort)).tag(effort)
                }
            }

            Picker(strings.textVerbosity, selection: $store.settings.textVerbosity) {
                ForEach(TextVerbosity.allCases) { verbosity in
                    Text(strings.verbosityName(verbosity)).tag(verbosity)
                }
            }

            Toggle(strings.stripTargetPunctuation, isOn: $store.settings.stripTargetPunctuation)

            Toggle(strings.contextAnalysisToggle, isOn: $store.settings.useContextAnalysis)

            Text(strings.contextAnalysisHint)
                .font(.caption)
                .foregroundStyle(AppTheme.mutedIvory)
        }
    }

    private var advancedSection: some View {
        let strings = store.strings

        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                NumericSettingRow(title: strings.concurrentRequests, suffix: strings.requestUnit, value: $store.settings.maxConcurrentRequests, range: 1...10, step: 1)
                NumericSettingRow(title: strings.cueLimit, suffix: strings.cueUnit, value: $store.settings.chunkCueLimit, range: 1...500, step: 4)
                NumericSettingRow(title: strings.characterLimit, suffix: strings.characterUnit, value: $store.settings.maxSourceCharacters, range: 500...50_000, step: 500)
                NumericSettingRow(title: strings.contextOverlap, suffix: strings.cueUnit, value: $store.settings.contextOverlap, range: 0...50, step: 1)
                NumericSettingRow(title: strings.retryLimit, suffix: strings.retryUnit, value: $store.settings.retryLimit, range: 0...10, step: 1)
                NumericSettingRow(title: strings.previewLimit, suffix: strings.cueUnit, value: $store.previewCueLimit, range: 50...20_000, step: 100)
            }
            .padding(.top, 8)
        } label: {
            Text(strings.advancedSettings)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.brass)
        }
        .tint(AppTheme.brass)
    }

    private func targetLanguageText(strings: AppStrings) -> Binding<String> {
        Binding(
            get: { strings.targetLanguageLabel(store.settings.targetLanguage) },
            set: { store.settings.targetLanguage = $0 }
        )
    }

    private var transcriptionSection: some View {
        let strings = store.strings

        return SettingsGroup(title: strings.transcriptionTab) {
            Text(strings.transcriptionHint)
                .font(.caption)
                .foregroundStyle(AppTheme.mutedIvory)

            Picker(strings.transcriptionEngine, selection: $store.settings.transcriptionEngine) {
                Text(strings.whisperLocalEngine).tag(TranscriptionEngine.whisperKit)
                Text(strings.typhoonEngine).tag(TranscriptionEngine.typhoon)
                Text(strings.scribeCloudEngine).tag(TranscriptionEngine.scribe)
            }
            .pickerStyle(.radioGroup)

            Picker(strings.spokenLanguage, selection: $store.settings.transcriptionLanguage) {
                Text(strings.autoDetectLanguage).tag("auto")
                Text("ไทย 泰语").tag("th")
                Text("English 英语").tag("en")
                Text("中文").tag("zh")
                Text("日本語 日语").tag("ja")
                Text("한국어 韩语").tag("ko")
            }

            if store.settings.transcriptionEngine == .whisperKit {
                Picker(strings.whisperModelName, selection: $store.settings.whisperModel) {
                    Text("large-v3").tag("large-v3")
                    Text("large-v3-turbo").tag("large-v3-v20240930")
                    Text("medium").tag("medium")
                    Text("small").tag("small")
                }

                Text(strings.whisperModelHint)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedIvory)
            } else if store.settings.transcriptionEngine == .typhoon {
                Text(TyphoonTranscriber.isInstalled ? strings.typhoonHint : strings.typhoonNotInstalled)
                    .font(.caption)
                    .foregroundStyle(TyphoonTranscriber.isInstalled ? AppTheme.mutedIvory : AppTheme.warning)

                if !TyphoonTranscriber.isInstalled {
                    Button {
                        store.installTyphoon()
                    } label: {
                        Label(strings.installTyphoon, systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isInstallingTyphoon)

                    if store.isInstallingTyphoon {
                        ProgressView()
                            .controlSize(.small)
                        Text(store.typhoonInstallStatus)
                            .font(.caption)
                            .foregroundStyle(AppTheme.mutedIvory)
                    }
                }
            } else {
                SettingsField(title: strings.scribeKey) {
                    SecureField(strings.scribeKey, text: $store.scribeAPIKey)
                }

                Text(strings.scribeHint)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedIvory)
            }
        }
    }

    private var memorySection: some View {
        let strings = store.strings

        return SettingsGroup(title: strings.backendMemory) {
            HStack {
                Label(strings.fixedTranslationCount(store.settings.translationMemory.count), systemImage: AppIconSymbol.memory)
                    .foregroundStyle(AppTheme.ivory)
                Spacer()
                Text(strings.memoryInjectedHint)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedIvory)
            }

            SettingsField(title: strings.sourceOrName) {
                TextField(strings.sourcePlaceholder, text: $memorySource)
            }

            SettingsField(title: strings.fixedTranslation) {
                TextField(strings.targetPlaceholder, text: $memoryTarget)
            }

            SettingsField(title: strings.note) {
                TextField(strings.notePlaceholder, text: $memoryNote)
            }

            HStack {
                Button {
                    store.addMemoryEntry(source: memorySource, target: memoryTarget, note: memoryNote)
                    memorySource = ""
                    memoryTarget = ""
                } label: {
                    Label(strings.addMemory, systemImage: AppIconSymbol.add)
                }

                Button {
                    store.restoreDefaultMemoryEntries()
                } label: {
                    Label(strings.restorePreset, systemImage: AppIconSymbol.reset)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(store.settings.translationMemory) { entry in
                    MemoryEntryRow(entry: entry, strings: strings) {
                        store.removeMemoryEntry(id: entry.id)
                    }
                }
            }
        }
    }

    private var promptSection: some View {
        let strings = store.strings

        return SettingsGroup(title: strings.translationPrompt) {
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
        let strings = store.strings

        return SettingsGroup(title: strings.validation) {
            LabeledContent(strings.totalCues, value: "\(store.validation.totalCues)")
            LabeledContent(strings.translated, value: "\(store.validation.translatedCues)")
            LabeledContent(strings.missing, value: "\(store.validation.missingIDs.count)")
            LabeledContent(strings.duplicates, value: "\(store.validation.duplicateIDs.count)")

            Button(role: .destructive) {
                store.clearTranslations()
            } label: {
                Label(strings.clearTranslations, systemImage: AppIconSymbol.clear)
            }
            .disabled(store.selectedDocument == nil || store.isTranslating)
        }
    }
}

private enum InspectorTab: String, CaseIterable, Identifiable {
    case model
    case transcription
    case memory
    case quality

    var id: String { rawValue }

    func title(strings: AppStrings) -> String {
        switch self {
        case .model:
            return strings.modelSettingsTab
        case .transcription:
            return strings.transcriptionTab
        case .memory:
            return strings.memoryTab
        case .quality:
            return strings.promptValidationTab
        }
    }

    var systemImage: String {
        switch self {
        case .model:
            return AppIconSymbol.modelSettings
        case .transcription:
            return AppIconSymbol.transcribe
        case .memory:
            return AppIconSymbol.memory
        case .quality:
            return AppIconSymbol.promptValidation
        }
    }
}

private struct InspectorTabBar: View {
    @Binding var selection: InspectorTab
    let strings: AppStrings

    var body: some View {
        HStack(spacing: 6) {
            ForEach(InspectorTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Label(tab.title(strings: strings), systemImage: tab.systemImage)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == tab ? AppTheme.ivory : AppTheme.mutedIvory)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selection == tab ? AppTheme.graphitePanel : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(selection == tab ? AppTheme.divider : .clear, lineWidth: 1)
                )
                .help(tab.title(strings: strings))
            }
        }
    }
}

private struct MemoryEntryRow: View {
    let entry: TranslationMemoryEntry
    let strings: AppStrings
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
                Image(systemName: AppIconSymbol.remove)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.mutedIvory)
            .help(strings.remove)
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
                .frame(width: 118, alignment: .leading)

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
