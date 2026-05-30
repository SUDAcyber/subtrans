import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 340)
        } detail: {
            HStack(spacing: 0) {
                WorkspaceView(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if store.isInspectorPresented {
                    Divider()
                        .overlay(AppTheme.graphitePanel)
                    InspectorView(store: store)
                        .frame(width: 372)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background(AppTheme.graphite)
            .animation(.smooth(duration: 0.22), value: store.isInspectorPresented)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.importWithPanel()
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .help("导入 SRT")

                Picker("目标语言", selection: $store.settings.targetLanguage) {
                    ForEach(["简体中文", "繁体中文", "英文", "日文", "韩文", "西班牙文", "法文", "德文"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 118)

                TextField("模型", text: $store.settings.model)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                if store.isTranslating {
                    Button {
                        store.cancelTranslation()
                    } label: {
                        Label("停止", systemImage: "pause.circle")
                    }
                    .help("停止翻译")
                } else {
                    Button {
                        store.translateSelected()
                    } label: {
                        Label("翻译", systemImage: "play.circle.fill")
                    }
                    .help("开始翻译")
                    .disabled(!store.canTranslate)
                }

                Button {
                    store.exportSelectedWithPanel()
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .help("导出 SRT")
                .disabled(store.selectedDocument == nil)

                Button {
                    store.isInspectorPresented.toggle()
                } label: {
                    Label("设置", systemImage: "sidebar.right")
                }
                .help("显示或隐藏设置")
            }
        }
        .alert("需要处理一下", isPresented: errorBinding) {
            Button("知道了") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .background(WindowDragConfigurator())
        .preferredColorScheme(.dark)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }
}
