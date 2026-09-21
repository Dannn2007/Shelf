import SwiftUI

// MARK: - 信息行

struct InfoRow<Content: View>: View {
    let title: String
    var icon: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 宽按钮

struct WideButton: View {
    let title: String
    let symbol: String
    var color: Color = .accentColor
    var prominent: Bool = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10.5))
                Text(title).font(.system(size: 11.5, weight: prominent ? .semibold : .medium))
            }
            .foregroundStyle(prominent ? .white : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent
                          ? AnyShapeStyle(color.gradient)
                          : AnyShapeStyle(color.opacity(hovered ? 0.18 : 0.11)))
            )
            .shadow(color: prominent ? color.opacity(0.35) : .clear, radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .opacity(hovered && !prominent ? 0.9 : 1.0)
    }
}
