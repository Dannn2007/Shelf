import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FileAreaView: View {
    @EnvironmentObject var store: ShelfStore
    @ObservedObject private var settings = ShelfSettings.shared
    @Binding var selection: Set<UUID>
    @Binding var tagFilter: ShelfTag?

    @State private var isTargeted = false

    private var module: ShelfModule? { store.module(with: store.selectedModuleID) }

    private var allItems: [ShelfItem] {
        guard let id = store.selectedModuleID else { return [] }
        return store.itemsByModule()[id] ?? []
    }

    private var visibleItems: [ShelfItem] {
        var items = allItems
        if let f = tagFilter, f != .none {
            items = items.filter { $0.tag == f }
        }
        let q = store.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            items = items.filter {
                $0.fileName.lowercased().contains(q) ||
                $0.note.lowercased().contains(q)
            }
        }
        return items
    }

    private var usedTags: [ShelfTag] {
        var set: [ShelfTag] = []
        for i in allItems where i.tag != .none && !set.contains(i.tag) { set.append(i.tag) }
        return set
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标签筛选条
            if !usedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        TagFilterChip(title: "全部", color: .secondary, active: tagFilter == nil) {
                            tagFilter = nil
                        }
                        ForEach(usedTags) { t in
                            TagFilterChip(title: t.label, color: t.color, active: tagFilter == t) {
                                tagFilter = (tagFilter == t) ? nil : t
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                ShelfDivider()
            }

            ZStack {
                if visibleItems.isEmpty && !allItems.isEmpty {
                    let searching = !store.searchText.isEmpty
                    EmptyStateView(symbol: searching ? "magnifyingglass" : "tag.slash",
                                   title: searching
                                       ? "没有匹配「「\(store.searchText)」」的文件"
                                       : "没有符合该标签的文件",
                                   subtitle: searching
                                       ? "换个关键词试试，或按 Esc 清除搜索。"
                                       : "换一个标签看看，或点上方「全部」。",
                                   accent: module?.accent ?? .accentColor)
                } else if allItems.isEmpty {
                    dropHint
                } else {
                    grid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(settings.appBackground)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .animation(.easeOut(duration: 0.2), value: usedTags.count)
    }

    // MARK: 拖放提示

    private var dropHint: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .foregroundStyle(isTargeted
                                 ? (module?.accent ?? .accentColor).opacity(0.85)
                                 : settings.appBorder)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill((module?.accent ?? .accentColor).opacity(isTargeted ? 0.10 : 0.02))
                )
                .padding(20)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill((module?.accent ?? .accentColor).opacity(0.14))
                        .frame(width: 78, height: 78)
                    Image(systemName: isTargeted ? "arrow.down.doc.fill" : "tray.and.arrow.down")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle((module?.accent ?? .accentColor).gradient)
                        // 拖着文件悬停时图标持续脉动，明确“可以松手了”
                        .symbolEffect(.pulse, options: .repeating, isActive: isTargeted)
                }
                Text(isTargeted ? "松手即可加入" : "把文件拖进这里")
                    .font(.system(size: 15, weight: .semibold))
                Text("只是给原文件建一个快捷方式，\n文件本身不会移动，位置保持不变。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: 网格

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 124, maximum: 144), spacing: 14)],
                      spacing: 14) {
                ForEach(visibleItems) { item in
                    FileTile(item: item,
                             isSelected: selection.contains(item.id),
                             accent: module?.accent ?? .accentColor,
                             onSelect: { select(item) },
                             onOpen: { open(item) })
                        .transition(.asymmetric(
                            // 切换模块 / 筛选时轻快淡入，不做大幅缩放——保证“点了立刻出现”
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 22)
        }
        // 拖入 / 移除 / 标签筛选变化时快速平滑过渡（短时长，弱弹簧）
        .animation(.easeOut(duration: 0.16), value: visibleItems.map(\.id))
    }

    private func select(_ item: ShelfItem) {
        if NSEvent.modifierFlags.contains(.command) {
            selection.formSymmetricDifference([item.id])
        } else if NSEvent.modifierFlags.contains(.shift) {
            selection.insert(item.id)
        } else {
            selection = [item.id]
        }
    }

    // MARK: 右键菜单

    private func contextMenu(for item: ShelfItem) -> some View {
        Group {
            Button("打开") { open(item) }
            Button("在 Finder 中显示") { reveal(item) }
            ShelfDivider()
            Menu("彩色标签") {
                Button("无标签") { setTag(item, .none) }
                ForEach(ShelfTag.pickable) { t in
                    Button(t.label) { setTag(item, t) }
                }
            }
            Button("编辑备注…") {
                selection = [item.id]
                NotificationCenter.default.post(name: .shelfFocusNote, object: nil)
            }
            ShelfDivider()
            Menu("移动到…") {
                ForEach(store.modules.filter { $0.id != item.moduleID }) { m in
                    Button(m.name) { store.moveItem(item.id, to: m.id) }
                }
            }
            ShelfDivider()
            Button("从模块中移除", role: .destructive) {
                selection.remove(item.id)
                store.removeItem(item.id)
            }
        }
    }

    // MARK: 行为

    private func open(_ item: ShelfItem) {
        guard let url = item.resolvedURL() else { return }
        store.markOpened(item.id)
        NSWorkspace.shared.open(url)
    }

    private func reveal(_ item: ShelfItem) {
        guard let url = item.resolvedURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func setTag(_ item: ShelfItem, _ tag: ShelfTag) {
        var i = item
        i.tagRaw = tag.rawValue
        store.updateItem(i)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let moduleID = store.selectedModuleID else { return false }
        // Shelf 内部拖拽（磁贴拖到侧边栏移动归属）不在网格里处理，避免意外复制
        let external = providers.filter {
            !$0.hasItemConformingToTypeIdentifier(ShelfMarkers.itemID)
        }
        guard !external.isEmpty else { return false }
        var handled = false
        for p in external {
            guard p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            handled = true
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                } else if let s = item as? String {
                    url = URL(string: s)
                }
                guard let url else { return }
                DispatchQueue.main.async {
                    _ = store.addItem(url: url, to: moduleID)
                }
            }
        }
        return handled
    }
}

// MARK: - 单个文件磁贴

struct FileTile: View {
    let item: ShelfItem
    let isSelected: Bool
    let accent: Color
    let onSelect: () -> Void
    let onOpen: () -> Void

    @EnvironmentObject private var store: ShelfStore
    @ObservedObject private var settings = ShelfSettings.shared
    @State private var hovered = false
    // bookmark 解析是文件系统 I/O，绝不能每次渲染都做。
    // 解析一次缓存起来，body 里的 url / missing / 路径全部读缓存。
    @State private var cachedURL: URL?
    @State private var urlResolved = false

    /// 固定高度，保证同一行的磁贴不会因为「有没有备注」而高低不齐
    private static let height: CGFloat = 132

    private var url: URL? { cachedURL }
    private var missing: Bool { urlResolved && cachedURL == nil }

    // 悬停做成「预选中」：跟选中同一色系，只是淡一档
    private var fill: Color {
        if isSelected { return accent.opacity(0.24) }
        if hovered    { return accent.opacity(0.13) }
        return settings.cardBackground
    }

    private var stroke: Color {
        if isSelected { return accent.opacity(0.9) }
        if hovered    { return accent.opacity(0.5) }
        return settings.appBorder
    }

    private var strokeWidth: CGFloat {
        if isSelected { return 2 }
        return hovered ? 1.5 : 1
    }

    private var displayPath: String {
        guard let url = cachedURL else { return "原文件已丢失" }
        return (url.path as NSString).deletingLastPathComponent
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var body: some View {
        // action 留空：单击（含 ⌘/⇧ 多选）由 pressing 在 mouse-down 瞬间处理，
        // 绕开双击判定窗口；Button 只提供 isPressed 视觉反馈
        Button(action: {}) {
            tileContent
        }
        .buttonStyle(TilePressStyle(fill: fill,
                                    stroke: stroke,
                                    lineWidth: strokeWidth,
                                    accent: accent,
                                    isSelected: isSelected,
                                    hovered: hovered))
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 30,
                            pressing: { pressing in
                                if pressing { onSelect() }
                            },
                            perform: {})
        .highPriorityGesture(TapGesture(count: 2).onEnded { onOpen() })
        .onDrag {
            guard let url else { return NSItemProvider() }
            return NSItemProvider(object: url as NSURL)
        }
        .contextMenu { contextMenu }
        .onHover { hovered = $0 }
        .onAppear { resolveIfNeeded() }
        .onChange(of: item.id) { resolveIfNeeded(force: true) }
        .help("\(item.fileName)\n\(displayPath)")
    }

    private func resolveIfNeeded(force: Bool = false) {
        if force || !urlResolved {
            cachedURL = item.resolvedURL()
            urlResolved = true
        }
    }

    private var tileContent: some View {
        VStack(spacing: 0) {
            // 图标 + 彩色标签角标
            ZStack(alignment: .topTrailing) {
                Group {
                    if let url {
                        FileIconView(url: url, size: 44)
                    } else {
                        Image(systemName: "questionmark.folder")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 48, height: 48)

                if item.tag != .none {
                    Circle()
                        .fill(item.tag.color)
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: 4, y: -3)
                }
            }
            .padding(.top, 13)

            // 文件名：固定两行的高度，不足两行也不塌陷
            Text(item.fileName)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(missing ? .secondary : .primary)
                .frame(height: 30, alignment: .top)
                .padding(.top, 9)

            // 副标题：备注 / 丢失提示 / 空白占位，始终占同一高度
            Group {
                if missing {
                    Text("原文件已丢失")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.red)
                } else if !item.note.isEmpty {
                    Text(item.note)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                        .font(.system(size: 10))
                }
            }
            .lineLimit(1)
            .frame(height: 14)
            .padding(.bottom, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private var contextMenu: some View {
        Group {
            Button("打开") { onOpen() }
            Button("在 Finder 中显示") { reveal() }
            ShelfDivider()
            Menu("彩色标签") {
                Button("无标签") { setTag(.none) }
                ForEach(ShelfTag.pickable) { t in
                    Button(t.label) { setTag(t) }
                }
            }
            Button("编辑备注…") {
                onSelect()
                NotificationCenter.default.post(name: .shelfFocusNote, object: nil)
            }
            ShelfDivider()
            Menu("移动到…") {
                ForEach(store.modules.filter { $0.id != item.moduleID }) { m in
                    Button(m.name) { store.moveItem(item.id, to: m.id) }
                }
            }
            ShelfDivider()
            Button("从模块中移除", role: .destructive) {
                store.removeItem(item.id)
            }
        }
    }

    private func reveal() {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func setTag(_ tag: ShelfTag) {
        var i = item
        i.tagRaw = tag.rawValue
        store.updateItem(i)
    }
}

// MARK: - 磁贴按下样式（即时反馈）

private struct TilePressStyle: ButtonStyle {
    let fill: Color
    let stroke: Color
    let lineWidth: CGFloat
    let accent: Color
    let isSelected: Bool
    let hovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(stroke, lineWidth: lineWidth)
            )
            .shadow(color: isSelected ? accent.opacity(0.25) : .black.opacity(hovered ? 0.12 : 0.06),
                    radius: isSelected ? 9 : (hovered ? 7 : 4), y: 2)
            .scaleEffect(configuration.isPressed ? 0.955 : 1.0)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.07), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.1), value: hovered)
            .animation(.easeOut(duration: 0.1), value: isSelected)
    }
}

// MARK: - 标签筛选芯片

struct TagFilterChip: View {
    let title: String
    let color: Color
    let active: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.system(size: 11.5, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(chipFill)
            )
            .overlay(
                Capsule().strokeBorder(active || hovered ? color.opacity(active ? 0.7 : 0.45) : Color.clear,
                                       lineWidth: 1.2)
            )
        }
        .buttonStyle(PressChipStyle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.1), value: hovered)
    }

    private var chipFill: Color {
        if active { return Color.primary.opacity(0.14) }
        if hovered { return color.opacity(0.1) }
        return Color.primary.opacity(0.05)
    }
}
