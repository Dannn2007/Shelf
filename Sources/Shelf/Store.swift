import Foundation
import SwiftUI
import AppKit

// MARK: - 设置（存 UserDefaults）

final class ShelfSettings: ObservableObject {
    static let shared = ShelfSettings()

    private enum Key {
        static let aiEnabled   = "ai.enabled"
        static let aiKey       = "ai.apiKey"
        static let aiModel     = "ai.model"
        static let aiBaseURL   = "ai.baseURL"
        static let hotKeyCode  = "hotkey.keyCode"
        static let hotKeyMods  = "hotkey.modifiers"
        static let showInspector = "ui.showInspector"
        static let borderHex     = "ui.borderHex"
        static let backgroundHex = "ui.backgroundHex"
    }

    private let ud = UserDefaults.standard

    @Published var aiEnabled: Bool {
        didSet { ud.set(aiEnabled, forKey: Key.aiEnabled) }
    }
    @Published var aiAPIKey: String {
        didSet { ud.set(aiAPIKey, forKey: Key.aiKey) }
    }
    @Published var aiModel: String {
        didSet { ud.set(aiModel, forKey: Key.aiModel) }
    }
    @Published var aiBaseURL: String {
        didSet { ud.set(aiBaseURL, forKey: Key.aiBaseURL) }
    }
    /// 默认 ⌥Space（keyCode 49 = 空格）
    @Published var hotKeyCode: UInt32 {
        didSet { ud.set(Int(hotKeyCode), forKey: Key.hotKeyCode) }
    }
    @Published var hotKeyModifiers: UInt32 {
        didSet { ud.set(Int(hotKeyModifiers), forKey: Key.hotKeyMods) }
    }
    @Published var showInspector: Bool {
        didSet { ud.set(showInspector, forKey: Key.showInspector) }
    }
    /// 全局边框色，nil = 跟随系统
    @Published var borderHex: String? {
        didSet { ud.set(borderHex, forKey: Key.borderHex) }
    }
    /// 全局背景色，nil = 跟随系统
    @Published var backgroundHex: String? {
        didSet { ud.set(backgroundHex, forKey: Key.backgroundHex) }
    }

    private init() {
        if ud.object(forKey: Key.hotKeyCode) == nil { ud.set(49, forKey: Key.hotKeyCode) }
        if ud.object(forKey: Key.hotKeyMods) == nil { ud.set(Int(0x0800), forKey: Key.hotKeyMods) } // option
        if ud.object(forKey: Key.aiModel) == nil { ud.set("deepseek-chat", forKey: Key.aiModel) }
        if ud.object(forKey: Key.aiBaseURL) == nil { ud.set("https://api.deepseek.com/chat/completions", forKey: Key.aiBaseURL) }

        self.aiEnabled   = ud.bool(forKey: Key.aiEnabled)
        self.aiAPIKey    = ud.string(forKey: Key.aiKey) ?? ""
        self.aiModel     = ud.string(forKey: Key.aiModel) ?? "deepseek-chat"
        self.aiBaseURL   = ud.string(forKey: Key.aiBaseURL) ?? "https://api.deepseek.com/chat/completions"
        self.hotKeyCode  = UInt32(ud.integer(forKey: Key.hotKeyCode))
        self.hotKeyModifiers = UInt32(ud.integer(forKey: Key.hotKeyMods))
        self.showInspector = ud.object(forKey: Key.showInspector) == nil ? true : ud.bool(forKey: Key.showInspector)
        self.borderHex     = ud.string(forKey: Key.borderHex)
        self.backgroundHex = ud.string(forKey: Key.backgroundHex)
    }
}

// MARK: - 全局配色派生

extension ShelfSettings {

    var globalBorder: Color?     { borderHex.flatMap { Color(hexString: $0) } }
    var globalBackground: Color? { backgroundHex.flatMap { Color(hexString: $0) } }

    /// 窗口 / 内容区底色
    var appBackground: Color {
        globalBackground ?? Color(nsColor: .windowBackgroundColor)
    }

    /// 卡片、面板的底色（在自定义背景上自动提亮或压暗一点，保证有层次）
    var cardBackground: Color {
        guard let c = globalBackground else { return Color.primary.opacity(0.03) }
        return c.adjusted(by: 0.07)
    }

    /// 普通边框。用户自定义时全强度使用（选了什么就是什么），
    /// 默认值才用低透明度中性色 —— 否则 1pt 彩色细线根本看不见，等于没生效
    var appBorder: Color {
        if let c = globalBorder { return c }
        return Color.primary.opacity(0.08)
    }

    /// 分割线（比边框淡一档）
    var appDivider: Color {
        if let c = globalBorder { return c.opacity(0.45) }
        return Color.primary.opacity(0.10)
    }
}

// MARK: - 主数据仓库

@MainActor
final class ShelfStore: ObservableObject {

    @Published var modules: [ShelfModule] = []
    @Published var items: [ShelfItem] = []
    @Published var rules: [LearnedRule] = []
    @Published var selectedModuleID: UUID?
    /// 每 15s 跳动一次，驱动临时分组的倒计时显示
    @Published var now: Date = Date()
    /// 搜索当前模块的文件名 / 备注（⌘F）
    @Published var searchText: String = ""

    private var tickTimer: Timer?

    static let shared = ShelfStore()

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("shelf.json")
    }()

    private init() {
        load()
        startTick()
    }

    /// 定时跳动：刷新倒计时显示 + 清理到期的临时分组
    private func startTick() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tick()
            }
        }
    }

    func tick() {
        now = Date()
        let expired = modules.filter { m in
            guard let e = m.expiresAt else { return false }
            return e <= now
        }
        guard !expired.isEmpty else { return }
        for m in expired {
            deleteModule(m.id)   // 只删除分组和其中的快捷方式，原文件不受影响
        }
    }

    // MARK: 临时分组

    func addTempGroup(name: String, hours: Double) {
        let m = ShelfModule(name: name,
                            symbol: "timer",
                            accentHex: "#FF9F0A",
                            keywords: [],
                            order: modules.count,
                            expiresAt: Date().addingTimeInterval(hours * 3600))
        modules.append(m)
        selectedModuleID = m.id
        save()
    }

    /// 延长临时分组寿命（从当前到期时间往后加）
    func extendTempGroup(_ id: UUID, byHours hours: Double = 1) {
        guard let i = modules.firstIndex(where: { $0.id == id }) else { return }
        guard modules[i].isTemporary else { return }
        let base = max(modules[i].expiresAt ?? Date(), Date())
        modules[i].expiresAt = base.addingTimeInterval(hours * 3600)
        save()
    }

    /// 取消倒计时，转为永久模块
    func cancelExpiry(_ id: UUID) {
        guard let i = modules.firstIndex(where: { $0.id == id }) else { return }
        modules[i].expiresAt = nil
        save()
    }

    // MARK: 读写

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let doc = try? JSONDecoder().decode(ShelfDocument.self, from: data) else {
            modules = SeedData.modules()
            items = []
            rules = []
            selectedModuleID = modules.first?.id
            save()
            return
        }
        modules = doc.modules.sorted { $0.order < $1.order }
        items = doc.items
        rules = doc.rules
        if selectedModuleID == nil || !modules.contains(where: { $0.id == selectedModuleID }) {
            selectedModuleID = modules.first?.id
        }
    }

    func save() {
        let doc = ShelfDocument(version: 1, modules: modules, items: items, rules: rules)
        guard let data = try? JSONEncoder().encode(doc) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: 模块

    func module(with id: UUID?) -> ShelfModule? {
        modules.first { $0.id == id }
    }

    func addModule(name: String, symbol: String, accentHex: String, keywords: [String],
                borderHex: String? = nil, backgroundHex: String? = nil) {
        let m = ShelfModule(name: name, symbol: symbol, accentHex: accentHex,
                            keywords: keywords, order: modules.count,
                            borderHex: borderHex, backgroundHex: backgroundHex)
        modules.append(m)
        selectedModuleID = m.id
        save()
    }

    func updateModule(_ m: ShelfModule) {
        guard let i = modules.firstIndex(where: { $0.id == m.id }) else { return }
        modules[i] = m
        save()
    }

    func deleteModule(_ id: UUID) {
        modules.removeAll { $0.id == id }
        items.removeAll { $0.moduleID == id }
        rules.removeAll { $0.moduleID == id }
        if selectedModuleID == id { selectedModuleID = modules.first?.id }
        save()
    }

    func moveModule(from source: IndexSet, to dest: Int) {
        modules.move(fromOffsets: source, toOffset: dest)
        for i in modules.indices { modules[i].order = i }
        save()
    }

    // MARK: 文件条目

    func items(in moduleID: UUID?) -> [ShelfItem] {
        items.filter { $0.moduleID == moduleID }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    /// 一次遍历完成分组 + 排序，供各视图共用（避免每行 / 每处各自全量 filter）
    func itemsByModule() -> [UUID: [ShelfItem]] {
        Dictionary(grouping: items, by: \.moduleID)
            .mapValues { $0.sorted { $0.dateAdded > $1.dateAdded } }
    }

    /// 一次遍历统计各模块文件数（侧边栏用）
    func itemCounts() -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for item in items { result[item.moduleID, default: 0] += 1 }
        return result
    }

    func item(with id: UUID?) -> ShelfItem? {
        items.first { $0.id == id }
    }

    private func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// 添加一个文件快捷方式。原文件保持不动，仅记录位置。
    /// - Returns: 是否新增成功（重复则 false）
    @discardableResult
    func addItem(url: URL, to moduleID: UUID) -> ShelfItem? {
        guard var data = makeBookmark(for: url) else { return nil }
        // 已存在相同 URL 则直接返回旧项
        if let existing = items.first(where: { $0.moduleID == moduleID && $0.resolvedURL()?.path == url.path }) {
            return existing
        }
        let item = ShelfItem(moduleID: moduleID,
                             fileName: url.lastPathComponent,
                             bookmark: data,
                             dateAdded: Date())
        data = Data()
        items.append(item)
        save()
        return item
    }

    func removeItem(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func removeItems(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func updateItem(_ item: ShelfItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i] = item
        save()
    }

    func moveItem(_ id: UUID, to moduleID: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].moduleID = moduleID
        save()
    }

    func markOpened(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].dateOpened = Date()
        save()
    }

    // MARK: 学习规则

    func learn(token: String, moduleID: UUID) {
        let t = token.lowercased()
        guard t.count >= 2 else { return }
        if let i = rules.firstIndex(where: { $0.token == t && $0.moduleID == moduleID }) {
            rules[i].hits += 1
            rules[i].updatedAt = Date()
        } else {
            rules.append(LearnedRule(token: t, moduleID: moduleID))
        }
        save()
    }

    func forgetRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    func clearRules() {
        rules = []
        save()
    }
}
