import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = ShelfSettings.shared

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("通用", systemImage: "gearshape") }
            AppearanceTab()
                .tabItem { Label("外观", systemImage: "paintbrush") }
            AITab()
                .tabItem { Label("AI 增强", systemImage: "sparkles") }
            RulesTab()
                .tabItem { Label("分类规则", systemImage: "list.bullet.rectangle") }
            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 470, height: 560)
    }
}

// MARK: - 外观（全局配色）

private struct AppearanceTab: View {
    @ObservedObject private var settings = ShelfSettings.shared

    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { settings.globalBackground ?? Color(nsColor: .windowBackgroundColor) },
            set: { settings.backgroundHex = $0.hexString() }
        )
    }

    private var borderBinding: Binding<Color> {
        Binding(
            get: { settings.globalBorder ?? Color.primary.opacity(0.08) },
            set: { settings.borderHex = $0.hexString() }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // 实时预览
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(settings.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(settings.appBorder, lineWidth: 1)
                        )
                        .frame(width: 62, height: 44)
                    Text("卡片")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(settings.appBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(settings.appBorder, lineWidth: 1)
                        )
                        .frame(width: 62, height: 44)
                    Text("背景")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                ShelfDivider(vertical: true).frame(height: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(settings.backgroundHex ?? "跟随系统")
                        .font(.system(size: 10, design: .monospaced))
                    Text(settings.borderHex ?? "跟随系统")
                        .font(.system(size: 10, design: .monospaced))
                }
                Spacer()
            }
            .padding(14)
            .background(Material.thin, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(14)

            ShelfDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    swatchSection(title: "背景色",
                                  binding: backgroundBinding,
                                  hasOverride: settings.backgroundHex != nil) {
                        settings.backgroundHex = nil
                    }
                    swatchSection(title: "边框色",
                                  binding: borderBinding,
                                  hasOverride: settings.borderHex != nil) {
                        settings.borderHex = nil
                    }
                    Text("留空或点「跟随系统」就回到 macOS 原生配色，自动适配深浅色。自定义后深浅切换不再生效。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
        }
    }

    private func swatchSection(title: String,
                               binding: Binding<Color>,
                               hasOverride: Bool,
                               onReset: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                if hasOverride {
                    Button("跟随系统", action: onReset)
                        .buttonStyle(.borderless)
                        .font(.system(size: 10.5))
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 10), count: 12), spacing: 10) {
                ForEach(ShelfSwatches.all.indices, id: \.self) { i in
                    let c = ShelfSwatches.all[i]
                    Button { binding.wrappedValue = c } label: {
                        ZStack {
                            Circle().fill(c).frame(width: 24, height: 24)
                            Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5).frame(width: 24, height: 24)
                            if binding.wrappedValue.hexString() == c.hexString() {
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
}

// MARK: - 通用

private struct GeneralTab: View {
    @ObservedObject private var settings = ShelfSettings.shared

    private let hotKeyOptions: [(label: String, code: UInt32, mods: UInt32)] = [
        ("⌥ 空格",   49, UInt32(0x0800)),
        ("⌃⌥ 空格",  49, UInt32(0x1800)),
        ("⇧⌥ 空格",  49, UInt32(0x0A00)),
        ("⌘⇧ S",    1,  UInt32(0x0300)),
        ("⌘⇧ Space", 49, UInt32(0x0300)),
        ("关闭",      0,  0)
    ]

    private var selectionIndex: Int {
        hotKeyOptions.firstIndex { $0.code == settings.hotKeyCode && $0.mods == settings.hotKeyModifiers } ?? 5
    }

    var body: some View {
        Form {
            Section {
                Toggle("显示右侧面板（自动分类 / 文件详情）", isOn: $settings.showInspector)
            } header: {
                Text("界面").font(.headline)
            }

            Section {
                Picker("呼出窗口：", selection: Binding(
                    get: { selectionIndex },
                    set: { idx in
                        let o = hotKeyOptions[idx]
                        settings.hotKeyCode = o.code
                        settings.hotKeyModifiers = o.mods
                        NotificationCenter.default.post(name: .shelfHotKeyChanged, object: nil)
                    })) {
                    ForEach(0..<hotKeyOptions.count, id: \.self) { i in
                        Text(hotKeyOptions[i].label).tag(i)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)

                Text("若该组合已被系统或其他 App 占用，Shelf 会自动尝试下一个可用组合。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } header: {
                Text("全局快捷键").font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

// MARK: - AI

private struct AITab: View {
    @ObservedObject private var settings = ShelfSettings.shared
    @EnvironmentObject var store: ShelfStore

    @State private var showKey = false
    @State private var testState: TestState = .idle

    enum TestState { case idle, running, ok(String), fail(String) }

    var body: some View {
        Form {
            Section {
                Toggle("启用 AI 增强分类", isOn: $settings.aiEnabled)
                Text("关闭时完全用本地规则判断，离线、零延迟、零成本。开启后，本地结果会先立刻显示，AI 判断随后叠加（需要联网）。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("开关").font(.headline)
            }

            Section {
                HStack {
                    Group {
                        if showKey {
                            TextField("sk-…", text: $settings.aiAPIKey)
                        } else {
                            SecureField("sk-…", text: $settings.aiAPIKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    Button(showKey ? "隐藏" : "显示") { showKey.toggle() }
                        .buttonStyle(.borderless)
                }
                TextField("模型", text: $settings.aiModel)
                    .textFieldStyle(.roundedBorder)
                TextField("接口地址", text: $settings.aiBaseURL)
                    .textFieldStyle(.roundedBorder)
                Text("默认已填 DeepSeek。任何 OpenAI 兼容接口都可用（如本机 Ollama 填 http://localhost:11434/v1/chat/completions）。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("接口").font(.headline)
            }

            Section {
                HStack {
                    Button("测试连接") { runTest() }
                        .disabled(settings.aiAPIKey.isEmpty || testState.isRunning)
                    if testState.isRunning { ProgressView().controlSize(.small).scaleEffect(0.7) }
                    Spacer()
                }
                switch testState {
                case .idle:
                    EmptyView()
                case .running:
                    EmptyView()
                case .ok(let msg):
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                case .fail(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("诊断").font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private func runTest() {
        let url = URL(fileURLWithPath: "/tmp/shelf_test_sample.pdf")
        testState = .running
        let fp = FileFingerprint(url: url)
        let modules = store.modules
        let key = settings.aiAPIKey, model = settings.aiModel, base = settings.aiBaseURL
        Task.detached {
            do {
                let s = try await AIClassifier.suggest(fp: fp, modules: modules,
                                                       apiKey: key, model: model, baseURL: base)
                await MainActor.run {
                    testState = .ok("连通：建议归入「\(s.primaryName)」")
                }
            } catch {
                await MainActor.run {
                    testState = .fail("连接失败：\(error.localizedDescription)")
                }
            }
        }
    }
}

private extension AITab.TestState {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

// MARK: - 规则

private struct RulesTab: View {
    @EnvironmentObject var store: ShelfStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("每次在分类卡片上勾选「记住这条规则」，Shelf 就会记下「这个词 → 这个模块」，下次同类文件会优先归到那里。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(14)

            ShelfDivider()

            if store.rules.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("还没有记住任何规则")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.rules.sorted { $0.updatedAt > $1.updatedAt }) { rule in
                        HStack(spacing: 8) {
                            Text(rule.token)
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            if let m = store.module(with: rule.moduleID) {
                                HStack(spacing: 4) {
                                    Image(systemName: m.symbol).font(.system(size: 9))
                                    Text(m.name).font(.system(size: 11.5))
                                }
                                .foregroundStyle(m.accent)
                            }
                            Spacer()
                            Text("×\(rule.hits)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Button {
                                store.forgetRule(rule.id)
                            } label: {
                                Image(systemName: "trash").font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)

                HStack {
                    Spacer()
                    Button("清空全部规则", role: .destructive) { store.clearRules() }
                }
                .padding(12)
            }
        }
    }
}

// MARK: - 关于

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .shadow(radius: 8, y: 3)

            Text("Shelf")
                .font(.system(size: 20, weight: .semibold))
            Text("版本 1.0")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                bullet("每个模块是一个收纳架，放进去的只是快捷方式")
                bullet("原文件永远不动，一键跳回它在 Finder 里的位置")
                bullet("把文件拖到右侧，自动判断该放进哪个模块")
            }
            .font(.system(size: 11.5))
            .padding(.top, 4)

            Spacer()

            Text("Made for Danny · 2026")
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·")
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}
