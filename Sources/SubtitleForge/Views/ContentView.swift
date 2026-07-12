import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: AppStore
    @State private var isFileDropTargeted = false

    var body: some View {
        let strings = store.strings

        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 340)
        } detail: {
            HStack(spacing: 0) {
                WorkspaceView(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if store.isInspectorPresented {
                    Divider()
                        .overlay(AppTheme.divider)
                    InspectorView(store: store)
                        .frame(width: 372)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background(AppTheme.graphite)
            .overlay {
                if isFileDropTargeted {
                    FileDropOverlay(strings: strings)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isFileDropTargeted) { providers in
                store.importDroppedProviders(providers)
            }
            .animation(.smooth(duration: 0.22), value: store.isInspectorPresented)
            .animation(.smooth(duration: 0.16), value: isFileDropTargeted)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.importWithPanel()
                } label: {
                    Label(strings.importAction, systemImage: AppIconSymbol.importFile)
                }
                .help(strings.importSRT)

                Button {
                    store.isFindReplacePresented.toggle()
                } label: {
                    Label(strings.findReplaceTranslation, systemImage: AppIconSymbol.search)
                }
                .help(strings.findReplaceTranslation)
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(store.selectedDocument == nil)

                if store.isBusy {
                    Button {
                        store.cancelTranslation()
                    } label: {
                        Label(strings.stop, systemImage: AppIconSymbol.stop)
                    }
                    .help(strings.stopTranslation)
                } else {
                    Button {
                        store.translateSelected()
                    } label: {
                        Label(strings.translate, systemImage: AppIconSymbol.translate)
                    }
                    .help(strings.startTranslation)
                    .disabled(!store.canTranslate)
                }

                Button {
                    store.isInspectorPresented.toggle()
                } label: {
                    Label(strings.settings, systemImage: AppIconSymbol.inspector)
                }
                .help(strings.showHideSettings)
            }
        }
        .alert(strings.alertTitle, isPresented: errorBinding) {
            Button(strings.ok) {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .preferredColorScheme(store.colorSchemeMode.preferredColorScheme)
        .background(WindowTitleUpdater(title: strings.appName))
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }
}

private struct WindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        updateTitle(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updateTitle(for: nsView)
    }

    private func updateTitle(for view: NSView) {
        DispatchQueue.main.async {
            view.window?.title = title
        }
    }
}

private struct FileDropOverlay: View {
    let strings: AppStrings

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: AppIconSymbol.addFile)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(AppTheme.brass)
            Text(strings.dropToImport)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ivory)
            Text(strings.dropMultipleFiles)
                .font(.callout)
                .foregroundStyle(AppTheme.mutedIvory)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.graphiteRaised)
                .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.brass.opacity(0.7), lineWidth: 1)
        )
    }
}
