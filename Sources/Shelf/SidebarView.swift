import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// sheet(item:) 的编辑目标。module 为 nil = 新建模式。
/// 用 item 驱动 sheet，保证编辑器拿到的一定是打开那一刻的模块快照，
/// 不存在「两个 @State 先后设置、sheet 先弹后赋值」的时序坑。
private struct EditorTarget: Identifiable {
    let id = UUID()
    let module: ShelfModule?
}

// MARK: - 侧边栏

struct SidebarView: View {
    @EnvironmentObject var store: ShelfStore
    @ObservedObject private var settings = ShelfSettings.shared
    @State private var editorTarget: EditorTarget?
    @State private var renamingID: UUID?
    @State private var showTempSheet = false
    @State private var dropTargetModuleID: UUID?
    @Namespace private var selectionNS

    var body: some View {
        // 一次遍历拿到所有模块的计数，避免 ForEach 里每行都全量 filter
        let counts = store.itemCounts()
        let permanent = store.modules.filter { !$0.isTemporary }
        let temporary = store.modules.filter { $0.isTemporary }

        VStack(spacing: 0) {
            List {
                Section("模块") {
                    ForEach(permanent) { module in
                        row(for: module, count: counts[module.id] ?? 0, timeBadge: nil)
                            .listRowBackground(moduleRowBackground(module))
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                            .onDrop(of: [.fileURL, .shelfItemID],
                                    isTargeted: Binding(
                                        get: { dropTargetModuleID == module.id },
                                        set: { dropTargetModuleID = $0 ? module.id : nil })) {
                                handleModuleDrop($0, moduleID: module.id)
                            }
                    }
                    .onMove(perform: store.moveModule)
                }

                if !temporary.isEmpty {
                    Section("临时 · 到期自动清理") {
                        ForEach(temporary) { module in
                            row(for: module,
                                count: counts[module.id] ?? 0,
                                timeBadge: remainingInfo(for: module))
                                .listRowBackground(moduleRowBackground(module))
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                                .onDrop(of: [.fileURL, .shelfItemID],
                                        isTargeted: Binding(
                                            get: { dropTargetModuleID == module.id },
                                            set: { dropTargetModuleID = $0 ? module.id : nil })) {
                                    handleModuleDrop($0, moduleID: module.id)
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            // 选中胶囊跨行滑动 —— 快弹簧，点了立刻到位
            .animation(.spring(response: 0.24, dampingFraction: 0.9),
                       value: store.selectedModuleID)
            .animation(.spring(response: 0.3, dampingFraction: 0.85),
                       value: store.modules.map(\.id))

            ShelfDivider()

            HStack(spacing: 6) {
                Button {
                    editorTarget = EditorTarget(module: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("新建模块")

                Button {
                    if let id = store.selectedModuleID {
                        withAnimation { store.deleteModule(id) }
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(store.selectedModuleID == nil)
                .help("删除选中模块")

                Button {
                    renamingID = store.selectedModuleID
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(store.selectedModuleID == nil)
                .help("重命名选中模块（也可直接双击模块名）")

                Button {
                    showTempSheet = true
                } label: {
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("新建临时分组（1-24 小时后自动清理）")

                Spacer()

                Button {
                    if let m = store.module(with: store.selectedModuleID) {
                        editorTarget = EditorTarget(module: m)
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(store.selectedModuleID == nil)
                .help("模块设置…（图标、配色、关键词）")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .sheet(isPresented: $showTempSheet) {
                TempGroupSheet()
                    .environmentObject(store)
            }
        }
        .background(settings.appBackground)
        .sheet(item: $editorTarget) { target in
            ModuleEditorView(editing: target.module)
                .environmentObject(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .shelfNewModule)) { _ in
            editorTarget = EditorTarget(module: nil)
        }
    }

    /// 行背景：拖放悬停高亮 > 选中胶囊
    @ViewBuilder
    private func moduleRowBackground(_ module: ShelfModule) -> some View {
        if dropTargetModuleID == module.id {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(module.accent.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(module.accent.opacity(0.85),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                )
                .padding(.horizontal, 6)
        } else {
            selectionCapsule(for: module)
        }
    }

    /// 侧边栏行接收拖放：
    /// - Shelf 内部磁贴拖上来 = 移动归属到该模块
    /// - 外部文件拖上来 = 新建快捷方式
    private func handleModuleDrop(_ providers: [NSItemProvider], moduleID: UUID) -> Bool {
        let isInternal = providers.contains {
            $0.hasItemConformingToTypeIdentifier(ShelfMarkers.itemID)
        }
        let isFile = providers.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard isInternal || isFile else { return false }

        for p in providers {
            if isInternal, p.hasItemConformingToTypeIdentifier(ShelfMarkers.itemID) {
                _ = p.loadDataRepresentation(forTypeIdentifier: ShelfMarkers.itemID) { data, _ in
                    guard let data,
                          let id = UUID(uuidString: String(data: data, encoding: .utf8) ?? "") else { return }
                    DispatchQueue.main.async {
                        store.moveItem(id, to: moduleID)
                    }
                }
            } else if !isInternal, p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = p.loadObject(ofClass: URL.self) { item, _ in
                    guard let url = item as URL? else { return }
                    DispatchQueue.main.async {
                        _ = store.addItem(url: url, to: moduleID)
                    }
                }
            }
        }
        return true
    }

    /// 选中胶囊：用 matchedGeometryEffect 让它在切换模块时平滑滑动过去
    @ViewBuilder
    private func selectionCapsule(for module: ShelfModule) -> some View {
        if store.selectedModuleID == module.id {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(module.selectedColor)
                .matchedGeometryEffect(id: "sidebar-selection", in: selectionNS)
                .padding(.horizontal, 6)
        } else {
            Color.clear
        }
    }

    // MARK: 行

    /// 剩余时间文案 + 是否紧急（<10 分钟变红）
    private func remainingInfo(for module: ShelfModule) -> (text: String, urgent: Bool)? {
        guard let e = module.expiresAt else { return nil }
        let remain = e.timeIntervalSince(store.now)
        if remain <= 0 { return ("到期", true) }
        let h = Int(remain) / 3600
        let m = (Int(remain) % 3600) / 60
        if h >= 1 { return ("\(h)h \(String(format: "%02d", m))m", false) }
        return ("\(m)m", remain < 600)
    }

    @ViewBuilder
    private func row(for module: ShelfModule, count: Int, timeBadge: (text: String, urgent: Bool)?) -> some View {
        let isSelected = store.selectedModuleID == module.id

        if renamingID == module.id {
            InlineRenameRow(module: module) { newName in
                var m = module
                m.name = newName
                store.updateModule(m)
                renamingID = nil
            } onCancel: {
                renamingID = nil
            }
        } else {
            ModuleRow(module: module,
                      count: count,
                      isSelected: isSelected,
                      onSelect: {
                          store.selectedModuleID = module.id
                      },
                      timeBadge: timeBadge?.text,
                      timeUrgent: timeBadge?.urgent ?? false)
            .highPriorityGesture(TapGesture(count: 2).onEnded {
                store.selectedModuleID = module.id
                renamingID = module.id
            })
            .contextMenu {
                if module.isTemporary {
                    Button("立即清理") {
                        withAnimation { store.deleteModule(module.id) }
                    }
                    Button("延长 1 小时") { store.extendTempGroup(module.id, byHours: 1) }
                    Button("取消倒计时（转为永久）") { store.cancelExpiry(module.id) }
                    Divider()
                    Button("模块设置…") {
                        editorTarget = EditorTarget(module: module)
                    }
                    Divider()
                    Button("删除模块", role: .destructive) {
                        withAnimation { store.deleteModule(module.id) }
                    }
                } else {
                    Button("重命名") { renamingID = module.id }
                    Button("模块设置…") {
                        editorTarget = EditorTarget(module: module)
                    }
                    Divider()
                    Button("删除模块", role: .destructive) {
                        withAnimation { store.deleteModule(module.id) }
                    }
                }
            }
        }
    }
}

// MARK: - 内联重命名

private struct InlineRenameRow: View {
    let module: ShelfModule
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var draft: String
    @FocusState private var focused: Bool
    @State private var finished = false

    init(module: ShelfModule, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.module = module
        self.onCommit = onCommit
        self.onCancel = onCancel
        _draft = State(initialValue: module.name)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: module.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(module.accent.gradient,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: module.accent.opacity(0.4), radius: 3, y: 1)

            TextField("模块名称", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($focused)
                .onSubmit { finish { commit() } }
                .onExitCommand { finish { onCancel() } }

            Button {
                finish { onCancel() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
        .onAppear {
            // 两个 runloop：先让 TextField 拿到焦点，再全选
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                focused = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
                }
            }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { finish { commit() } }
        }
    }

    private func finish(_ action: () -> Void) {
        guard !finished else { return }
        finished = true
        action()
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == module.name {
            onCancel()
        } else {
            onCommit(trimmed)
        }
    }
}

struct ModuleRow: View {
    let module: ShelfModule
    let count: Int
    let isSelected: Bool
    let onSelect: () -> Void
    var timeBadge: String? = nil
    var timeUrgent: Bool = false

    @State private var hovered = false

    // 悬停 = 预选中。选中态由 matchedGeometry 选中胶囊负责，这里不再画
    private var fill: Color {
        if hovered { return module.accent.opacity(0.11) }
        return Color.clear
    }

    var body: some View {
        // action 留空：单击由下方 pressing（mouse-down 瞬间）立即处理，
        // 避免被双击判定窗口拖慢约 0.3s。Button 只提供 isPressed 视觉反馈。
        Button(action: {}) {
            rowContent
        }
        .buttonStyle(SidebarRowStyle(fill: fill,
                                     accent: module.accent,
                                     isSelected: isSelected))
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 30,
                            pressing: { pressing in
                                if pressing { onSelect() }
                            },
                            perform: {})
        .onHover { hovered = $0 }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Image(systemName: module.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(module.accent.gradient,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: module.accent.opacity(isSelected || hovered ? 0.5 : 0.28),
                        radius: isSelected ? 5 : 3, y: 2)

            Text(module.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 4)

            if let timeBadge {
                // 临时分组：剩余时间徽章（<10 分钟变红）
                Text(timeBadge)
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: timeBadge)
                    .foregroundStyle(timeUrgent ? Color.red : module.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill((timeUrgent ? Color.red : module.accent)
                            .opacity(isSelected || hovered ? 0.2 : 0.13))
                    )
            } else if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(isSelected || hovered ? module.accent : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(isSelected || hovered
                                       ? module.accent.opacity(0.16)
                                       : Color.primary.opacity(0.07))
                    )
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 侧边栏行的按下反馈
private struct SidebarRowStyle: ButtonStyle {
    let fill: Color
    let accent: Color
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.07), value: configuration.isPressed)
    }
}

// MARK: - 模块编辑器

struct ModuleEditorView: View {
    @EnvironmentObject var store: ShelfStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = ShelfSettings.shared

    let editing: ShelfModule?

    @State private var name: String = ""
    @State private var symbol: String = "folder.fill"
    @State private var accent: Color = Color(hex: 0x0A84FF)
    @State private var border: Color?    // nil = 跟随强调色
    @State private var background: Color? // nil = 跟随强调色
    @State private var keywordsText: String = ""

    private let palette: [Color] = [
        Color(hex: 0x0A84FF), Color(hex: 0x5E5CE6), Color(hex: 0xBF5AF2), Color(hex: 0xFF375F),
        Color(hex: 0xFF453A), Color(hex: 0xFF9F0A), Color(hex: 0xFFD60A), Color(hex: 0x30D158),
        Color(hex: 0x64D2FF), Color(hex: 0x66D4CF), Color(hex: 0xAC8E68), Color(hex: 0x98989D)
    ]

    private let symbols = [
        "folder.fill", "tray.full.fill", "archivebox.fill", "book.fill", "books.vertical.fill",
        "graduationcap.fill", "atom", "waveform.path.ecg", "chart.line.uptrend.xyaxis",
        "chevron.left.forwardslash.chevron.right", "flask.fill", "laptopcomputer", "hammer.fill",
        "paintbrush.fill", "camera.fill", "photo.fill", "film.stack.fill", "gamecontroller.fill",
        "heart.fill", "star.fill", "flag.fill", "tag.fill", "briefcase.fill", "cart.fill",
        "banknote.fill", "dollarsign.circle.fill", "house.fill", "building.2.fill", "airplane",
        "car.fill", "bicycle", "figure.walk", "person.fill", "person.3.fill", "leaf.fill",
        "flame.fill", "bolt.fill", "drop.fill", "snowflake", "sun.max.fill", "moon.fill",
        "globe", "network", "cpu.fill", "opticaldisc", "waveform",
        "antenna.radiowaves.left.and.right", "sparkles", "lightbulb.fill", "pencil",
        "doc.text.fill", "calendar", "clock.fill", "bell.fill", "gearshape.fill", "lock.fill",
        "key.fill", "paperclip", "link", "square.grid.2x2.fill", "circle.grid.2x2.fill",
        "cube.fill", "puzzlepiece.fill", "doc.richtext.fill", "newspaper.fill"
    ]

    init(editing: ShelfModule?) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _symbol = State(initialValue: editing?.symbol ?? "folder.fill")
        _accent = State(initialValue: editing?.accent ?? Color(hex: 0x0A84FF))
        _border = State(initialValue: editing?.borderHex.flatMap(Color.init(hexString:)))
        _background = State(initialValue: editing?.backgroundHex.flatMap(Color.init(hexString:)))
        _keywordsText = State(initialValue: (editing?.keywords ?? []).joined(separator: ", "))
    }

    /// 用于预览 / 实际显示的边框色
    private var effectiveBorder: Color { border ?? accent.opacity(0.45) }
    private var effectiveBackground: Color { background ?? accent.opacity(0.13) }

    private var parsedKeywords: [String] {
        keywordsText
            .components(separatedBy: CharacterSet(charactersIn: ",，、;；\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // 预览
            HStack(spacing: 14) {
                // 模块图标
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(accent.gradient,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: accent.opacity(0.45), radius: 10, y: 4)

                // 实时徽章预览（标题栏里那种）
                HStack(spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(accent.gradient,
                                    in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                    Text(name.isEmpty ? "新模块" : name)
                        .font(.system(size: 13, weight: .semibold))
                    Text("0")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(effectiveBorder.opacity(0.35)))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(effectiveBackground))
                .overlay(Capsule().strokeBorder(effectiveBorder.opacity(0.6), lineWidth: 0.75))

                Spacer()
            }
            .padding(16)
            .background(Material.thin, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(16)

            ShelfDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        fieldTitle("名称")
                        TextField("例如 Study", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                    }

                    colorSection(title: "强调色",
                                 binding: $accent,
                                 allowAutoReset: false,
                                 autoHex: nil)

                    colorSection(title: "边框色",
                                 binding: Binding(
                                    get: { border ?? Color.primary.opacity(0.4) },
                                    set: { border = $0 }),
                                 allowAutoReset: true,
                                 autoHex: nil) {
                        border = nil
                    }

                    colorSection(title: "背景色",
                                 binding: Binding(
                                    get: { background ?? Color.primary.opacity(0.15) },
                                    set: { background = $0 }),
                                 allowAutoReset: true,
                                 autoHex: nil) {
                        background = nil
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        fieldTitle("图标")
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 10), spacing: 8) {
                            ForEach(symbols, id: \.self) { s in
                                Button {
                                    symbol = s
                                } label: {
                                    Image(systemName: s)
                                        .font(.system(size: 15))
                                        .foregroundStyle(s == symbol ? .white : .primary)
                                        .frame(width: 34, height: 30)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(s == symbol ? accent : Color.primary.opacity(0.07))
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(s)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        fieldTitle("分类关键词")
                        Text("自动分类会拿这些词去匹配文件名和路径。用逗号或换行分隔。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $keywordsText)
                            .font(.system(size: 12))
                            .frame(minHeight: 76)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(settings.appBorder, lineWidth: 1)
                            )
                    }
                }
                .padding(16)
            }

            ShelfDivider()

            HStack {
                if editing != nil {
                    Button("删除", role: .destructive) {
                        if let e = editing { store.deleteModule(e.id) }
                        dismiss()
                    }
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "创建" : "保存") {
                    commit()
                    dismiss()
                }
                .buttonStyle(AccentButtonStyle(color: accent))
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding(16)
        }
        .frame(width: 480, height: 640)
    }

    private func fieldTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    /// 色块 + ColorPicker + 可选的「跟随强调色」恢复按钮
    @ViewBuilder
    private func colorSection(title: String,
                              binding: Binding<Color>,
                              allowAutoReset: Bool,
                              autoHex: String?,
                              onAuto: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                fieldTitle(title)
                if allowAutoReset {
                    Button {
                        onAuto?()
                    } label: {
                        Text("跟随强调色")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 10), count: 12), spacing: 10) {
                ForEach(palette, id: \.self) { c in
                    Button {
                        binding.wrappedValue = c
                    } label: {
                        ZStack {
                            Circle().fill(c.gradient).frame(width: 24, height: 24)
                            if isSameColor(c, binding.wrappedValue) {
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: 2)
                                    .frame(width: 28, height: 28)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                }
            }
            HStack {
                ColorPicker("自定义", selection: binding)
                    .labelsHidden()
                    .frame(width: 50, height: 22)
                Text(binding.wrappedValue.hexString())
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 比较两个 Color 是否视觉上相同（hex 字符串归一化比较）
    private func isSameColor(_ a: Color, _ b: Color) -> Bool {
        a.hexString().caseInsensitiveCompare(b.hexString()) == .orderedSame
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let bHex = border?.hexString()
        let bgHex = background?.hexString()
        if var e = editing {
            e.name = trimmed
            e.symbol = symbol
            e.accentHex = accent.hexString()
            e.borderHex = bHex
            e.backgroundHex = bgHex
            e.keywords = parsedKeywords
            store.updateModule(e)
        } else {
            store.addModule(name: trimmed,
                            symbol: symbol,
                            accentHex: accent.hexString(),
                            keywords: parsedKeywords,
                            borderHex: bHex,
                            backgroundHex: bgHex)
        }
    }
}


// MARK: - 新建临时分组

private struct TempGroupSheet: View {
    @EnvironmentObject var store: ShelfStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var hours: Double = 4

    private let options: [Double] = [1, 2, 4, 8, 12, 24]

    var body: some View {
        VStack(spacing: 0) {
            // 头部说明
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color(hex: 0xFF9F0A).gradient,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color(hex: 0xFF9F0A).opacity(0.4), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text("新建临时分组")
                        .font(.system(size: 16, weight: .semibold))
                    Text("到期后自动删除该分组及其中的快捷方式，原文件不受影响")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("名称")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("例如：今天要发的文件（留空则自动命名）", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("保留时长")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $hours) {
                        ForEach(options, id: \.self) { h in
                            Text(h < 1 ? "30m" : "\(Int(h)) 小时").tag(h)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text("创建于今天 \(Date().formatted(date: .omitted, time: .shortened))，" +
                         "将在 \(expiryText) 自动清理。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: 0xFF9F0A))
                    Text("临时分组同样可以参与自动分类：在「模块设置…」里给它加关键词。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("创建") {
                    let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.addTempGroup(name: finalName.isEmpty ? "临时分组" : finalName,
                                       hours: hours)
                    dismiss()
                }
                .buttonStyle(AccentButtonStyle(color: Color(hex: 0xFF9F0A)))
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 420, height: 340)
    }

    private var expiryText: String {
        let d = Date().addingTimeInterval(hours * 3600)
        return d.formatted(date: .abbreviated, time: .shortened)
    }
}
