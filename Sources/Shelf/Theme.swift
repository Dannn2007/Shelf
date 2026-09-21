import SwiftUI

// MARK: - 通用圆角

/// 全局共享的预设调色板
enum ShelfSwatches {
    static let all: [Color] = [
        Color(hex: 0x0A84FF), Color(hex: 0x5E5CE6), Color(hex: 0xBF5AF2), Color(hex: 0xFF375F),
        Color(hex: 0xFF453A), Color(hex: 0xFF9F0A), Color(hex: 0xFFD60A), Color(hex: 0x30D158),
        Color(hex: 0x64D2FF), Color(hex: 0x66D4CF), Color(hex: 0xAC8E68), Color(hex: 0x98989D),
        Color(hex: 0x1C1C1E), Color(hex: 0x2C2C2E), Color(hex: 0x48484A), Color(hex: 0x8E8E93),
        Color(hex: 0xF2F2F7), Color(hex: 0xFFFFFF)
    ]
}

enum ShelfMetrics {
    static let cardRadius: CGFloat = 16
    static let smallRadius: CGFloat = 10
    static let chipRadius: CGFloat = 8
    static let sidebarWidth: CGFloat = 228
    static let inspectorMinWidth: CGFloat = 280
    static let inspectorMaxWidth: CGFloat = 360
}

/// 接入全局边框色的分割线。替代系统 Divider()（系统分割线不接自定义配色）。
struct ShelfDivider: View {
    @ObservedObject private var settings = ShelfSettings.shared
    var vertical = false

    var body: some View {
        let color = settings.appDivider
        Group {
            if vertical {
                Rectangle().fill(color).frame(width: 1)
            } else {
                Rectangle().fill(color).frame(height: 1)
            }
        }
    }
}

// MARK: - 毛玻璃卡片

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = ShelfMetrics.cardRadius
    var material: Material = .thick
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 5)
    }
}

// MARK: - 主按钮样式

struct AccentButtonStyle: ButtonStyle {
    var color: Color = .accentColor
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: ShelfMetrics.smallRadius, style: .continuous)
                    .fill(color.gradient)
                    .opacity(configuration.isPressed ? 0.82 : 1.0)
                    .shadow(color: color.opacity(0.35), radius: configuration.isPressed ? 2 : 7, y: 3)
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 次要按钮

struct SoftButtonStyle: ButtonStyle {
    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: ShelfMetrics.chipRadius, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.16 : 0.1))
            )
    }
}

// MARK: - 窗口访问器（用来配置原生窗口外观）

struct WindowAccessor: NSViewRepresentable {
    var configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window { configure(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { configure(window) }
        }
    }
}

// MARK: - 文件图标

struct FileIconView: View {
    let url: URL
    var size: CGFloat = 44

    /// 图标缓存：NSWorkspace.icon(forFile:) 是文件系统调用，
    /// 网格里几十个磁贴同时加载时会卡主线程，缓存后每个路径只解析一次
    private static let iconCache = NSCache<NSString, NSImage>()

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "doc")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear(perform: load)
        .onChange(of: url) { load() }
    }

    private func load() {
        let key = url.path as NSString
        if let cached = Self.iconCache.object(forKey: key) {
            image = cached
            return
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size * 2, height: size * 2)
        Self.iconCache.setObject(icon, forKey: key)
        image = icon
    }
}

// MARK: - 通用按压反馈（芯片 / 小按钮）

/// 按下时轻微缩放 + 压暗，统一全 App 芯片类控件的手感
struct PressChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.easeOut(duration: 0.07), value: configuration.isPressed)
    }
}

// MARK: - 空状态

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var subtitle: String
    var accent: Color = .accentColor

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // 外圈柔光 + 内环描边，比纯色圆更有层次
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 84, height: 84)
                    .blur(radius: 2)
                Circle()
                    .fill(accent.opacity(0.10))
                    .frame(width: 76, height: 76)
                Circle()
                    .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                    .frame(width: 76, height: 76)
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(accent.gradient)
            }
            .shadow(color: accent.opacity(0.25), radius: 12, y: 4)

            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
