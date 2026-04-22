import AppKit
import CoreGraphics

/// `GlassUITheme` 把散落在各视图文件中的设计常量统一收口。
/// 任何视觉调整只需改这一个文件，组件层通过符号引用自动跟随。
enum GlassUITheme {

    /// 圆角半径常量。对应各层级玻璃组件的 `cornerRadius` 默认值。
    enum CornerRadius {
        /// GlassPanel 默认圆角。
        static let large: CGFloat = 22
        /// GlassCard 默认圆角。
        static let medium: CGFloat = 18
        /// GlassListRowButtonStyle 默认圆角。
        static let extraSmall: CGFloat = 16
        /// GlassIconButtonStyle 默认圆角。
        static let compact: CGFloat = 12
    }

    /// 内边距常量。对应各层级玻璃组件的 `padding` 默认值。
    enum Padding {
        /// GlassPanel 默认内边距。
        static let `default`: CGFloat = 14
        /// GlassCard 默认内边距。
        static let compact: CGFloat = 12
    }

    /// 菜单栏状态栏相关尺寸常量。
    enum MenuBar {
        /// 胶囊提醒态状态栏按钮的最大允许宽度，防止长标题把按钮撑得过宽。
        static let maxCapsuleStatusItemLength: CGFloat = 220
        /// 弹出层固定内容尺寸，避免 NSHostingController 安装时触发递归布局警告。
        static let popoverContentSize = NSSize(width: 324, height: 270)
        /// 胶囊背景态额外补偿宽度，用于保证左右留白视觉对称。
        static let extraWidth: CGFloat = 12
    }
}
