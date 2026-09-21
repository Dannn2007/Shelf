import SwiftUI
import AppKit

extension Notification.Name {
    static let shelfOpenSettings = Notification.Name("ShelfOpenSettings")
}

struct ContentView: View {
    @EnvironmentObject var store: ShelfStore
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var settings = ShelfSettings.shared

    @State private var selection: Set<UUID> = []
    @State private var tagFilter: ShelfTag?
    @State private var showSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var currentModule: ShelfModule? { store.module(with: store.selectedModuleID) }
    private var itemCount: Int {
        guard let id = store.selectedModuleID else { return 0 }
        return store.itemCounts()[id] ?? 0
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .frame(minWidth: 186)
                .navigationSplitViewColumnWidth(min: 186, ideal: ShelfMetrics.sidebarWidth, max: 320)
        } detail: {
            HSplitView {
                FileAreaView(selection: $selection, tagFilter: $tagFilter)
                    .frame(minWidth: 420, idealWidth: 580)

                if settings.showInspector {
                    InspectorView(settings: settings, selection: $selection)
                        .frame(minWidth: ShelfMetrics.inspectorMinWidth,
                               idealWidth: 300,
                               maxWidth: ShelfMetrics.inspectorMaxWidth)
                }
            }
        }
        .searchable(text: $store.searchText,
                    placement: .toolbar,
                    prompt: "搜索当前模块的文件或备注")
        .frame(minWidth: 860, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    if let m = currentModule {
                        moduleBadge(m)
                    } else {
                        Text("Shelf")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { settings.showInspector.toggle() }
                } label: {
                    Image(systemName: settings.showInspector ? "sidebar.right" : "rectangle.split.3x1")
                        .font(.system(size: 13))
                }
                .help(settings.showInspector ? "隐藏右侧面板" : "显示右侧面板")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                }
                .keyboardShortcut(",", modifiers: .command)
                .help("偏好设置")
            }
        }
        .background(WindowAccessor { window in
            configure(window)
        })
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .onAppear {
            AppState.shared.openMainWindow = { openWindow(id: "main") }
        }
        .onChange(of: store.selectedModuleID) {
            selection = []
            tagFilter = nil
            store.searchText = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .shelfSelectModule)) { note in
            if let id = note.object as? UUID { store.selectedModuleID = id }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shelfOpenSettings)) { _ in
            showSettings = true
        }
    }

    private func configure(_ window: NSWindow) {
        AppState.shared.mainWindow = window
        guard !window.identifierRaw.contains("configured") else { return }
        window.identifierRaw += "configured"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 860, height: 520)
        window.backgroundColor = NSColor.windowBackgroundColor
    }

    /// 自绘的模块徽章：模块图标 + 名字 + 计数
    /// 颜色用模块的 border/background（用户可自定义），不再被系统 toolbar 自动套 chrome
    @ViewBuilder
    private func moduleBadge(_ m: ShelfModule) -> some View {
        HStack(spacing: 7) {
            Image(systemName: m.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(m.accent.gradient,
                            in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                .shadow(color: m.accent.opacity(0.35), radius: 2, y: 1)

            Text(m.name)
                .font(.system(size: 13, weight: .semibold))

            Text("\(itemCount)")
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: itemCount)
                .foregroundStyle(m.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(m.borderColor.opacity(0.35))
                )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(m.backgroundColor)
        )
        .overlay(
            Capsule().strokeBorder(m.borderColor.opacity(0.6), lineWidth: 0.75)
        )
        .shadow(color: m.borderColor.opacity(0.18), radius: 4, y: 1)
    }
}

private extension NSWindow {
    var identifierRaw: String {
        get { (identifier?.rawValue) ?? "" }
        set { identifier = NSUserInterfaceItemIdentifier(newValue) }
    }
}
