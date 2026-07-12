import AppKit
import SwiftUI

@main
struct SubtitleForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        let strings = store.strings

        WindowGroup(strings.appName, id: "main") {
            ContentView(store: store)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(strings.importSRTCommand) {
                    store.importWithPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandMenu(strings.subtitleMenu) {
                Button(strings.startTranslation) {
                    store.translateSelected()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!store.canTranslate)

                Button(strings.stopTranslation) {
                    store.cancelTranslation()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!store.isBusy)

                Divider()

                Button(strings.exportSRTCommand) {
                    store.exportSelectedWithPanel()
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(store.selectedDocument == nil)
            }
        }

        Settings {
            AppSettingsView(store: store)
        }
    }
}

private struct AppSettingsView: View {
    @Bindable var store: AppStore

    var body: some View {
        let strings = store.strings

        Form {
            Picker(strings.appLanguage, selection: $store.interfaceLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }

            Picker(strings.theme, selection: $store.colorSchemeMode) {
                ForEach(AppColorSchemeMode.allCases) { mode in
                    Text(mode.displayName(language: store.interfaceLanguage)).tag(mode)
                }
            }

            Text(strings.appearanceHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
