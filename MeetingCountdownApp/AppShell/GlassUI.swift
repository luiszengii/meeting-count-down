import AppKit
import SwiftUI

/// 这个文件集中定义“接近 macOS 控制中心”的展示组件。
/// 它只负责材质、圆角、边框、按压态和浅色叠层，不承载任何业务逻辑，
/// 让菜单弹层和设置页可以共享同一套视觉语言。

/// `GlassMotion` 把这轮 UI 微动效统一收口成一组短时动画常量。
/// 这样不同视图在 hover、按压、切页时会维持一致节奏，不会某处很硬、某处很飘。
enum GlassMotion {
    static let hover = Animation.snappy(duration: 0.18, extraBounce: 0)
    static let press = Animation.smooth(duration: 0.12)
    static let page = Animation.snappy(duration: 0.24, extraBounce: 0.02)
    static let segmentedSelection = Animation.snappy(duration: 0.28, extraBounce: 0.02)
    static let segmentedLabel = Animation.easeInOut(duration: 0.2)
}

/// 这类装饰型控件不需要接管键盘焦点。
/// 统一关闭 focusable 可以避免 macOS 默认的蓝色方框破坏玻璃风格。
private struct GlassQuietFocusModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.focusable(false)
    }
}

extension View {
    /// 给纯视觉控件关闭默认焦点边框。
    func glassQuietFocus() -> some View {
        modifier(GlassQuietFocusModifier())
    }
}

/// `GlassMaterialView` 用 AppKit 的 `NSVisualEffectView` 提供真正的 macOS 毛玻璃材质。
/// SwiftUI 自带的 `Material` 在简单场景足够，但要尽量接近系统控制中心的层次感，
/// 仍然更适合直接桥接 AppKit 的材质视图。
struct GlassMaterialView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let emphasized: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let effectView = NSVisualEffectView()
        effectView.state = .active
        effectView.material = material
        effectView.blendingMode = blendingMode
        effectView.isEmphasized = emphasized
        return effectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = emphasized
    }
}

/// `GlassBackdrop` 提供大面积底板材质，并叠一层非常轻的渐变色，
/// 让界面既保留系统毛玻璃，又带一点你参考图里的暖冷混合气氛。
struct GlassBackdrop: View {
    var body: some View {
        ZStack {
            GlassMaterialView(
                material: .hudWindow,
                blendingMode: .behindWindow,
                emphasized: false
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.14),
                    Color(red: 1.0, green: 0.91, blue: 0.73).opacity(0.18),
                    Color(red: 0.82, green: 0.94, blue: 0.72).opacity(0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

/// `GlassPanel` 统一表达浮层和设置页里的圆角玻璃卡片。
struct GlassPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let overlayOpacity: Double
    @ViewBuilder let content: Content

    init(
        cornerRadius: CGFloat = 22,
        padding: CGFloat = 14,
        overlayOpacity: Double = 0.18,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.overlayOpacity = overlayOpacity
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    GlassMaterialView(
                        material: .popover,
                        blendingMode: .behindWindow,
                        emphasized: false
                    )

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(overlayOpacity))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 22, x: 0, y: 14)
    }
}

/// 小号卡片用于概览卡、设置块和次级信息面板。
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let tintOpacity: Double
    @ViewBuilder let content: Content

    init(
        cornerRadius: CGFloat = 18,
        padding: CGFloat = 12,
        tintOpacity: Double = 0.22,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.tintOpacity = tintOpacity
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(tintOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            }
    }
}

/// 胶囊按钮统一入口。
struct GlassPillButtonStyle: ButtonStyle {
    enum Tone {
        case primary
        case secondary
        case destructive
    }

    let tone: Tone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor(configuration.isPressed))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(borderColor.opacity(configuration.isPressed ? 0.2 : 0.38), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .glassQuietFocus()
            .animation(GlassMotion.press, value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch tone {
        case .primary:
            return .white
        case .secondary:
            return Color.primary.opacity(0.88)
        case .destructive:
            return .red
        }
    }

    private var borderColor: Color {
        switch tone {
        case .primary:
            return .black
        case .secondary:
            return .white
        case .destructive:
            return .red
        }
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        switch tone {
        case .primary:
            return Color.black.opacity(isPressed ? 0.92 : 0.98)
        case .secondary:
            return Color.white.opacity(isPressed ? 0.28 : 0.22)
        case .destructive:
            return Color.white.opacity(isPressed ? 0.16 : 0.1)
        }
    }
}

/// 小型图标按钮专门给刷新、更多等次级动作使用。
/// 它通过轻微 hover 底板和按压缩放提供反馈，同时去掉 macOS 默认焦点方框。
struct GlassIconButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 12) {
        self.cornerRadius = cornerRadius
    }

    func makeBody(configuration: Configuration) -> some View {
        GlassIconButtonStyleBody(
            configuration: configuration,
            cornerRadius: cornerRadius
        )
    }
}

private struct GlassIconButtonStyleBody: View {
    let configuration: GlassIconButtonStyle.Configuration
    let cornerRadius: CGFloat

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovering ? 1.02 : 1))
            .glassQuietFocus()
            .onHover { isHovering = $0 }
            .animation(GlassMotion.hover, value: isHovering)
            .animation(GlassMotion.press, value: configuration.isPressed)
    }

    private var backgroundColor: Color {
        if configuration.isPressed {
            return Color.white.opacity(0.22)
        }

        if isHovering {
            return Color.white.opacity(0.18)
        }

        return Color.clear
    }

    private var borderColor: Color {
        if configuration.isPressed {
            return Color.white.opacity(0.26)
        }

        if isHovering {
            return Color.white.opacity(0.18)
        }

        return Color.clear
    }
}

/// 列表行按钮用更轻的 hover 高亮，避免底部命令区完全没有交互反馈。
struct GlassListRowButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }

    func makeBody(configuration: Configuration) -> some View {
        GlassListRowButtonStyleBody(
            configuration: configuration,
            cornerRadius: cornerRadius
        )
    }
}

private struct GlassListRowButtonStyleBody: View {
    let configuration: GlassListRowButtonStyle.Configuration
    let cornerRadius: CGFloat

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .glassQuietFocus()
            .onHover { isHovering = $0 }
            .animation(GlassMotion.hover, value: isHovering)
            .animation(GlassMotion.press, value: configuration.isPressed)
    }

    private var backgroundColor: Color {
        if configuration.isPressed {
            return Color.white.opacity(0.16)
        }

        if isHovering {
            return Color.white.opacity(0.12)
        }

        return Color.clear
    }

    private var borderColor: Color {
        if configuration.isPressed {
            return Color.white.opacity(0.18)
        }

        if isHovering {
            return Color.white.opacity(0.12)
        }

        return Color.clear
    }
}

/// 轻量 badge 用于卡片上的小状态标签。
struct GlassBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(0.18), lineWidth: 1)
            )
    }
}

/// 设置页导航 pill。
struct GlassSegmentedTabs<Selection: Hashable & CaseIterable & Identifiable>: View where Selection.AllCases: RandomAccessCollection {
    let selection: Binding<Selection>
    let title: (Selection) -> String

    @Namespace private var selectionBackgroundNamespace
    @State private var hoveredItemID: Selection.ID?

    /// 选中态文字显式压到深灰，而不是继续跟随浅色玻璃背景一起发白，
    /// 这样在亮色胶囊上能稳定保持对比度。
    private let selectedLabelColor = Color(red: 0.18, green: 0.2, blue: 0.24)
    /// 未选中项仍然保留轻一点的灰蓝色，继续维持玻璃面板上的层级。
    private let unselectedLabelColor = Color(red: 0.9, green: 0.93, blue: 0.97).opacity(0.9)

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(Selection.allCases), id: \.id) { item in
                Button {
                    withAnimation(GlassMotion.segmentedSelection) {
                        selection.wrappedValue = item
                    }
                } label: {
                    Text(title(item))
                        .font(.system(size: 12, weight: selection.wrappedValue == item ? .bold : .semibold))
                        .foregroundStyle(
                            selection.wrappedValue == item
                                ? selectedLabelColor
                                : unselectedLabelColor
                        )
                        .scaleEffect(selection.wrappedValue == item ? 1 : 0.98)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background {
                            ZStack {
                                if hoveredItemID == item.id, selection.wrappedValue != item {
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.12))
                                        .transition(.opacity)
                                }

                                if selection.wrappedValue == item {
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.82))
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 1)
                                        .matchedGeometryEffect(
                                            id: "glass-segmented-selection",
                                            in: selectionBackgroundNamespace
                                        )
                                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                                }
                            }
                        }
                        .animation(GlassMotion.segmentedLabel, value: selection.wrappedValue == item)
                }
                .buttonStyle(.plain)
                .glassQuietFocus()
                .onHover { isHovering in
                    hoveredItemID = isHovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
                }
            }
        }
        .padding(5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.16))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
        )
        .animation(GlassMotion.hover, value: hoveredItemID)
        .animation(GlassMotion.segmentedSelection, value: selection.wrappedValue.id)
    }
}
