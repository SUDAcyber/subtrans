import SubtitleForgeCore

struct AppStrings {
    let language: AppLanguage

    var appName: String { language.appName }
    var projectManagement: String { choose("项目管理", "Project Management") }
    var settings: String { choose("设置", "Settings") }
    var close: String { choose("关闭", "Close") }
    var importAction: String { choose("导入", "Import") }
    var importSRT: String { choose("导入 SRT", "Import SRT") }
    var importSRTCommand: String { choose("导入 SRT...", "Import SRT...") }
    var selectSubtitleFiles: String { choose("选择一个或多个 SRT 字幕文件", "Choose one or more SRT subtitle files") }
    var targetLanguage: String { choose("目标语言", "Target Language") }
    var model: String { choose("模型", "Model") }
    var appearance: String { choose("外观", "Appearance") }
    var switchAppearance: String { choose("切换外观", "Switch appearance") }
    var stop: String { choose("停止", "Stop") }
    var stopTask: String { choose("停止任务", "Stop Task") }
    var stopTranslation: String { choose("停止翻译", "Stop Translation") }
    var startTranslation: String { choose("开始翻译", "Start Translation") }
    var translate: String { choose("翻译", "Translate") }
    var export: String { choose("导出", "Export") }
    var exportSRT: String { choose("导出 SRT", "Export SRT") }
    var exportSRTCommand: String { choose("导出 SRT...", "Export SRT...") }
    var showHideSettings: String { choose("显示或隐藏设置", "Show or hide settings") }
    var alertTitle: String { choose("需要处理一下", "Needs Attention") }
    var ok: String { choose("知道了", "OK") }
    var dropToImport: String { choose("松开以导入 SRT", "Release to Import SRT") }
    var dropMultipleFiles: String { choose("支持一次拖入多个字幕文件", "Drop one or more subtitle files") }
    var subtitleMenu: String { choose("字幕", "Subtitles") }
    var history: String { choose("历史记录", "History") }
    var trash: String { choose("回收箱", "Trash") }
    var moveToTrash: String { choose("移到回收箱", "Move to Trash") }
    var restore: String { choose("恢复", "Restore") }
    var permanentlyDelete: String { choose("永久删除", "Delete Permanently") }
    var autoDelete15Days: String { choose("15 天后自动删除", "Deletes after 15 days") }
    var modelSettingsTab: String { choose("模型设置", "Model") }
    var memoryTab: String { choose("记忆库", "Memory") }
    var promptValidationTab: String { choose("指令校验", "Prompt & Check") }
    var appLanguage: String { choose("界面语言", "Interface Language") }
    var theme: String { choose("主题", "Theme") }
    var appearanceHint: String {
        choose("默认跟随 macOS 系统外观 也可以手动固定为浅色或深色",
               "Follow macOS by default, or pin the app to light or dark mode")
    }
    var provider: String { choose("接口", "Provider") }
    var providerName: String { choose("接口名称", "Provider Name") }
    var providerURL: String { choose("接口地址", "Base URL") }
    var apiKey: String { choose("密钥", "API Key") }
    var modelName: String { choose("模型名称", "Model Name") }
    var endpointMode: String { choose("接口模式", "Endpoint") }
    var customTargetLanguage: String { choose("自定义目标语言", "Custom Target Language") }
    var reasoningEffort: String { choose("推理深度", "Reasoning") }
    var textVerbosity: String { choose("输出长度", "Verbosity") }
    var stripTargetPunctuation: String { choose("移除目标标点", "Remove target punctuation") }
    var chunking: String { choose("分段", "Chunking") }
    var cueLimit: String { choose("每批条数", "Cues per Batch") }
    var characterLimit: String { choose("字符上限", "Character Limit") }
    var contextOverlap: String { choose("上下文", "Context") }
    var retryLimit: String { choose("失败重试", "Retries") }
    var previewLimit: String { choose("预览数量", "Preview Limit") }
    var advancedSettings: String { choose("高级", "Advanced") }
    var concurrentRequests: String { choose("并发请求", "Concurrency") }
    var requestUnit: String { choose("路", "reqs") }
    var contextAnalysisToggle: String { choose("翻译前分析剧情", "Analyze story before translating") }
    var contextAnalysisHint: String {
        choose("先用一次请求生成剧情摘要和术语表 注入每个批次 让并发翻译保持人名和语气一致",
               "One extra request builds a plot summary and glossary shared by every batch, keeping names and tone consistent while batches run in parallel")
    }
    var cueUnit: String { choose("条", "cues") }
    var characterUnit: String { choose("字", "chars") }
    var retryUnit: String { choose("次", "tries") }
    var backendMemory: String { choose("后台记忆库", "Backend Memory") }
    var memoryInjectedHint: String { choose("会随每次翻译一起注入", "Injected into every translation request") }
    var sourceOrName: String { choose("原文或名字", "Source or Name") }
    var fixedTranslation: String { choose("固定译法", "Fixed Translation") }
    var note: String { choose("备注", "Note") }
    var sourcePlaceholder: String { choose("例如 Ko Song 或 เซิร์ฟ", "e.g. Ko Song or เซิร์ฟ") }
    var targetPlaceholder: String { choose("例如 Ko Song 或 Surf", "e.g. Ko Song or Surf") }
    var notePlaceholder: String { choose("例如 泰语人名", "e.g. Thai proper name") }
    var addMemory: String { choose("加入记忆", "Add to Memory") }
    var restorePreset: String { choose("恢复预置", "Restore Presets") }
    var translationPrompt: String { choose("翻译指令", "Translation Prompt") }
    var validation: String { choose("校验", "Validation") }
    var totalCues: String { choose("总条数", "Total Cues") }
    var translated: String { choose("已翻译", "Translated") }
    var missing: String { choose("缺失", "Missing") }
    var duplicates: String { choose("重复序号", "Duplicate IDs") }
    var clearTranslations: String { choose("清空译文", "Clear Translations") }
    var remove: String { choose("移除", "Remove") }
    var batch: String { choose("批次", "Batch") }
    var progress: String { choose("进度", "Progress") }
    var taskProgress: String { choose("任务进度", "Task Progress") }
    var generateSubtitle: String { choose("生成字幕", "Generate Subtitle") }
    var saveAs: String { choose("另存为", "Save As") }
    var searchTranslation: String { choose("查找译文", "Find Translation") }
    var replaceWith: String { choose("替换为", "Replace With") }
    var matchCase: String { choose("区分大小写", "Match Case") }
    var replaceOne: String { choose("替换一个", "Replace One") }
    var replaceAll: String { choose("全部替换", "Replace All") }
    var findReplaceTranslation: String { choose("查找替换译文", "Find & Replace Translation") }
    var source: String { choose("原文", "Source") }
    var translation: String { choose("译文", "Translation") }
    var idTimeline: String { choose("ID / 时间轴", "ID / Timeline") }
    var reviewName: String { choose("检查人名", "Check Name") }
    var pendingTranslation: String { choose("待翻译", "Pending") }
    var emptyTitle: String { choose("导入 SRT", "Import SRT") }
    var emptySubtitle: String {
        choose("本地锁定序号和时间轴 分批翻译后再重建字幕",
               "Keep IDs and timecodes local, translate in batches, then rebuild the SRT")
    }
    var chooseSubtitleFile: String { choose("选择字幕文件", "Choose Subtitle File") }
    var idle: String { choose("待命", "Idle") }
    var parsing: String { choose("正在解析", "Parsing") }
    var stopped: String { choose("已停止", "Stopped") }
    var translationsCleared: String { choose("译文已清空", "Translations cleared") }
    var movedToTrash: String { choose("已移到回收箱", "Moved to trash") }
    var restored: String { choose("已恢复", "Restored") }
    var permanentlyDeleted: String { choose("已永久删除", "Deleted permanently") }
    var exported: String { choose("已导出", "Exported") }
    var noTranslatableSubtitles: String { choose("没有可翻译的字幕", "No subtitles to translate") }
    var alreadyComplete: String { choose("译文已完整", "All cues already translated") }
    var analyzingContext: String { choose("正在分析剧情与术语", "Analyzing story and terminology") }
    var startTranslating: String { choose("开始翻译", "Starting translation") }
    var translationComplete: String { choose("翻译完成", "Translation complete") }
    var finishedWithMissing: String { choose("完成但仍有缺失", "Finished with missing items") }
    var failed: String { choose("失败", "Failed") }
    var missingSourceFolder: String {
        choose("这个字幕没有原始文件夹信息 请使用导出字幕选择保存位置",
               "This subtitle has no original folder information. Use Export to choose a save location.")
    }
    var noExportableSubtitle: String { choose("没有可导出的字幕", "No subtitle to export") }
    var importFileFirst: String { choose("请先导入字幕文件", "Import a subtitle file first") }
    var fillAPIKey: String { choose("请先在右侧填写密钥", "Enter an API key in Settings first") }
    var unreadableDroppedFile: String { choose("无法读取拖入的文件", "Could not read the dropped file") }
    var onlySRTDrop: String { choose("目前只支持拖入 SRT 字幕文件", "Only SRT subtitle files can be dropped") }
    var enterSearchText: String { choose("请先输入要查找的译文", "Enter translation text to find first") }
    var noTranslationMatch: String { choose("没有找到匹配译文", "No matching translation found") }
    var memoryNeedsSourceAndTarget: String { choose("记忆库需要同时填写原文和固定译法", "Memory entries need both source and fixed translation") }

    var targetLanguageOptions: [(value: String, label: String)] {
        [
            ("简体中文", choose("简体中文", "Simplified Chinese")),
            ("繁体中文", choose("繁体中文", "Traditional Chinese")),
            ("英文", choose("英文", "English")),
            ("日文", choose("日文", "Japanese")),
            ("韩文", choose("韩文", "Korean")),
            ("西班牙文", choose("西班牙文", "Spanish")),
            ("法文", choose("法文", "French")),
            ("德文", choose("德文", "German")),
            ("葡萄牙文", choose("葡萄牙文", "Portuguese")),
            ("俄文", choose("俄文", "Russian"))
        ]
    }

    func targetLanguageLabel(_ value: String) -> String {
        targetLanguageOptions.first { $0.value == value }?.label ?? value
    }

    func cueCount(_ count: Int) -> String {
        choose("\(count) 条", "\(count) cues")
    }

    func cueCountWithSize(count: Int, size: String) -> String {
        choose("\(count) 条 · \(size)", "\(count) cues · \(size)")
    }

    func imported(count: Int) -> String {
        choose("已导入 \(count) 条", "Imported \(count) cues")
    }

    func generated(_ fileName: String) -> String {
        choose("已生成 \(fileName)", "Generated \(fileName)")
    }

    func reviewWarnings(_ count: Int) -> String {
        choose("有 \(count) 条疑似人名需要检查", "\(count) possible names need review")
    }

    func matchCount(_ count: Int) -> String {
        choose("\(count) 处", "\(count) matches")
    }

    func fixedTranslationCount(_ count: Int) -> String {
        choose("\(count) 条固定译法", "\(count) fixed translations")
    }

    func previewLimited(limit: Int, total: Int) -> String {
        choose("已为界面性能限制预览前 \(limit) 条 导出仍包含全部 \(total) 条",
               "Preview limited to the first \(limit) cues for UI performance. Export still includes all \(total) cues.")
    }

    func replacedOne() -> String {
        choose("已替换 1 处", "Replaced 1 match")
    }

    func replacedAll(_ count: Int) -> String {
        count > 0 ? choose("已替换 \(count) 处", "Replaced \(count) matches") : noTranslationMatch
    }

    func validating(batch: Int, total: Int) -> String {
        choose("校验第 \(batch)/\(total) 批", "Validating batch \(batch)/\(total)")
    }

    func translating(batch: Int, total: Int) -> String {
        choose("翻译第 \(batch)/\(total) 批", "Translating batch \(batch)/\(total)")
    }

    func translatingProgress(completed: Int, total: Int) -> String {
        choose("已完成 \(completed)/\(total) 批", "Completed \(completed)/\(total) batches")
    }

    func finishedMissing(count: Int) -> String {
        choose("完成 仍有 \(count) 条缺失 再次点击开始翻译可补翻",
               "Finished with \(count) cues missing. Run translate again to fill them.")
    }

    func retrying(batch: Int, attempt: Int, totalAttempts: Int) -> String {
        choose("重试第 \(batch) 批 \(attempt)/\(totalAttempts)", "Retrying batch \(batch) \(attempt)/\(totalAttempts)")
    }

    func completeGenerated(_ fileName: String) -> String {
        choose("翻译完成 已生成 \(fileName)", "Translation complete. Generated \(fileName)")
    }

    func validationSummary(_ report: ValidationReport) -> String {
        if report.totalCues == 0 { return choose("未导入", "Not imported") }
        if report.isComplete { return choose("完整", "Complete") }
        if !report.duplicateIDs.isEmpty { return choose("序号重复 \(report.duplicateIDs.count)", "\(report.duplicateIDs.count) duplicate IDs") }
        if !report.missingIDs.isEmpty { return choose("缺失 \(report.missingIDs.count)", "\(report.missingIDs.count) missing") }
        return "\(report.translatedCues)/\(report.totalCues)"
    }

    func colorSchemeName(_ mode: AppColorSchemeMode) -> String {
        switch mode {
        case .system:
            return choose("跟随系统", "System")
        case .light:
            return choose("浅色", "Light")
        case .dark:
            return choose("深色", "Dark")
        }
    }

    func endpointName(_ endpoint: TranslationEndpoint) -> String {
        switch endpoint {
        case .chatCompletions:
            return choose("聊天补全", "Chat Completions")
        case .responses:
            return choose("Responses 接口", "Responses")
        }
    }

    func reasoningName(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none:
            return choose("模型默认", "Model Default")
        case .low:
            return choose("低", "Low")
        case .medium:
            return choose("中", "Medium")
        case .high:
            return choose("高", "High")
        }
    }

    func verbosityName(_ verbosity: TextVerbosity) -> String {
        switch verbosity {
        case .low:
            return choose("短", "Low")
        case .medium:
            return choose("中", "Medium")
        case .high:
            return choose("长", "High")
        }
    }

    private func choose(_ zhHans: String, _ english: String) -> String {
        switch language {
        case .zhHans:
            return zhHans
        case .english:
            return english
        }
    }
}
