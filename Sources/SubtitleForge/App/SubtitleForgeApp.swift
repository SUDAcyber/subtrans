import AppKit
import SwiftUI

@main
struct SubtitleForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("字幕锻造", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入 SRT...") {
                    store.importWithPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandMenu("字幕") {
                Button("开始翻译") {
                    store.translateSelected()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!store.canTranslate)

                Button("停止翻译") {
                    store.cancelTranslation()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!store.isTranslating)

                Divider()

                Button("导出 SRT...") {
                    store.exportSelectedWithPanel()
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(store.selectedDocument == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
