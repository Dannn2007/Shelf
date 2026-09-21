import Foundation
import UniformTypeIdentifiers
import SwiftUI
import AppKit

// MARK: - 彩色标签

enum ShelfTag: String, Codable, CaseIterable, Identifiable {
    case none, red, orange, yellow, green, blue, purple, gray

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:   return "无标签"
        case .red:    return "红"
        case .orange: return "橙"
        case .yellow: return "黄"
        case .green:  return "绿"
        case .blue:   return "蓝"
        case .purple: return "紫"
        case .gray:   return "灰"
        }
    }

    var color: Color {
        switch self {
        case .none:   return .clear
        case .red:    return Color(hex: 0xFF453A)
        case .orange: return Color(hex: 0xFF9F0A)
        case .yellow: return Color(hex: 0xFFD60A)
        case .green:  return Color(hex: 0x30D158)
        case .blue:   return Color(hex: 0x0A84FF)
        case .purple: return Color(hex: 0xBF5AF2)
        case .gray:   return Color(hex: 0x98989D)
        }
    }

    static var pickable: [ShelfTag] { [.red, .orange, .yellow, .green, .blue, .purple, .gray] }
}

// MARK: - 模块

struct ShelfModule: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var symbol: String
    var accentHex: String
    var keywords: [String]
    var order: Int
    var borderHex: String?
    var backgroundHex: String?
    /// 非空 = 临时分组，到期自动删除（nil = 永久模块）
    var expiresAt: Date?

    init(id: UUID = UUID(),
         name: String,
         symbol: String,
         accentHex: String,
         keywords: [String],
         order: Int = 0,
         borderHex: String? = nil,
         backgroundHex: String? = nil,
         expiresAt: Date? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.accentHex = accentHex
        self.keywords = keywords
        self.order = order
        self.borderHex = borderHex
        self.backgroundHex = backgroundHex
        self.expiresAt = expiresAt
    }

    var isTemporary: Bool { expiresAt != nil }

    var accent: Color { Color(hexString: accentHex) ?? .accentColor }

    /// 边框色：自定义优先，否则按强调色派生
    var borderColor: Color {
        if let hex = borderHex, let c = Color(hexString: hex) { return c }
        return accent.opacity(0.45)
    }

    /// 背景色：自定义优先，否则按强调色派生
    var backgroundColor: Color {
        if let hex = backgroundHex, let c = Color(hexString: hex) { return c }
        return accent.opacity(0.13)
    }

    /// 选中态用，比 backgroundColor 稍深
    var selectedColor: Color {
        if let hex = backgroundHex, let c = Color(hexString: hex) { return c.opacity(0.22) }
        return accent.opacity(0.22)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, accentHex, keywords, order, borderHex, backgroundHex, expiresAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decode(String.self, forKey: .symbol)
        accentHex = try c.decode(String.self, forKey: .accentHex)
        keywords = try c.decode([String].self, forKey: .keywords)
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        borderHex = try c.decodeIfPresent(String.self, forKey: .borderHex)
        backgroundHex = try c.decodeIfPresent(String.self, forKey: .backgroundHex)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
    }
}

// MARK: - 文件条目（快捷方式）

struct ShelfItem: Identifiable, Codable, Hashable {
    var id: UUID
    var moduleID: UUID
    var fileName: String
    var bookmark: Data
    var note: String
    var tagRaw: String
    var dateAdded: Date
    var dateOpened: Date?

    init(id: UUID = UUID(),
         moduleID: UUID,
         fileName: String,
         bookmark: Data,
         note: String = "",
         tagRaw: String = ShelfTag.none.rawValue,
         dateAdded: Date = Date(),
         dateOpened: Date? = nil) {
        self.id = id
        self.moduleID = moduleID
        self.fileName = fileName
        self.bookmark = bookmark
        self.note = note
        self.tagRaw = tagRaw
        self.dateAdded = dateAdded
        self.dateOpened = dateOpened
    }

    var tag: ShelfTag { ShelfTag(rawValue: tagRaw) ?? .none }

    /// 解析出原始文件的真实 URL。原文件被移动/重命名后通常仍能解析；被删除则返回 nil。
    func resolvedURL() -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        return url
    }

    var isMissing: Bool { resolvedURL() == nil }

    /// 原文件所在文件夹（用于「在 Finder 中显示」）
    var containingFolder: URL? { resolvedURL()?.deletingLastPathComponent() }

    var displayPath: String {
        guard let url = resolvedURL() else { return "原文件已丢失" }
        return (url.path as NSString).deletingLastPathComponent
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }
}

// MARK: - 学到的分类规则

struct LearnedRule: Identifiable, Codable, Hashable {
    var id: UUID
    var token: String        // 归一化后的关键词/扩展名
    var moduleID: UUID
    var hits: Int
    var updatedAt: Date

    init(id: UUID = UUID(), token: String, moduleID: UUID, hits: Int = 1, updatedAt: Date = Date()) {
        self.id = id
        self.token = token
        self.moduleID = moduleID
        self.hits = hits
        self.updatedAt = updatedAt
    }
}

// MARK: - 持久化文档

struct ShelfDocument: Codable {
    var version: Int
    var modules: [ShelfModule]
    var items: [ShelfItem]
    var rules: [LearnedRule]
}

// MARK: - 预置模块

enum SeedData {
    static func modules() -> [ShelfModule] {
        let specs: [(String, String, UInt32, [String])] = [
            ("Study", "book.fill", 0x0A84FF,
             ["course", "lecture", "hw", "homework", "exam", "note", "notes", "slides",
              "tutorial", "assignment", "study", "quiz", "midterm", "final",
              "课程", "笔记", "作业", "考试"]),
            ("Research", "flask.fill", 0xBF5AF2,
             ["research", "paper", "experiment", "lab", "data", "analysis", "dataset",
              "thesis", "journal", "figure", "result", "论文", "实验", "研究"]),
            ("Writing", "text.book.closed", 0xFF9F0A,
             ["writing", "essay", "draft", "document", "review", "citation", "abstract",
              "outline", "report", "doc", "写作", "文档", "报告"]),
            ("Work", "briefcase.fill", 0x64D2FF,
             ["work", "meeting", "minutes", "client", "invoice", "contract", "task",
              "plan", "todo", "工作", "会议", "任务"]),
            ("Projects", "chevron.left.forwardslash.chevron.right", 0x30D158,
             ["project", "code", "repo", "git", "swift", "python", "app", "src",
              "main", "build", "script", "项目", "代码"]),
            ("Personal", "person.crop.circle", 0xFF375F,
             ["personal", "id", "passport", "resume", "cv", "photo", "certificate",
              "insurance", "bank", "visa", "个人", "证件"]),
            ("Finance", "chart.line.uptrend.xyaxis", 0xFFD60A,
             ["finance", "etf", "stock", "fund", "portfolio", "invest", "dividend",
              "broker", "trade", "asset", "budget", "基金", "股票", "投资", "理财"])
        ]
        return specs.enumerated().map { idx, s in
            ShelfModule(name: s.0,
                        symbol: s.1,
                        accentHex: String(format: "#%06X", s.2),
                        keywords: s.3,
                        order: idx)
        }
    }
}

// MARK: - 拖拽标记

enum ShelfMarkers {
    /// 拖拽 payload 里的私有标记：带此标记 = Shelf 内部条目在拖动（载荷为条目 UUID 字符串），
    /// 侧边栏收到后执行「移动到该模块」；不带 = 外部文件拖入（新建快捷方式）
    static let itemID = "com.danny.shelf.item"
}

extension UTType {
    static let shelfItemID = UTType(ShelfMarkers.itemID) ?? .plainText
}

// MARK: - Color 扩展

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: opacity)
    }

    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }

    func hexString() -> String {
        // 必须用 .sRGB 回读：颜色都是按 sRGB 创建的，
        // 用 .deviceRGB 会做伽马转换，每次保存 hex 都会漂移几个色阶
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// 按感知亮度提亮或压暗：深色底变亮、浅色底变暗。用于让卡片浮在自定义背景之上。
    func adjusted(by amount: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let lum = 0.299 * ns.redComponent + 0.587 * ns.greenComponent + 0.114 * ns.blueComponent
        let delta = lum < 0.5 ? amount : -amount
        func clamp(_ v: CGFloat) -> Double { min(1.0, max(0.0, Double(v) + delta)) }
        return Color(red: clamp(ns.redComponent),
                     green: clamp(ns.greenComponent),
                     blue: clamp(ns.blueComponent),
                     opacity: Double(ns.alphaComponent))
    }
}
