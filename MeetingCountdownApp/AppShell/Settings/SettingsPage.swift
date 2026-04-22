import SwiftUI

// MARK: - SettingsPage 协议与注册表辅助

/// 每个设置页都实现这个协议；SettingsView 通过注册表轮转渲染。
///
/// ## 协议形状选择
///
/// 任务要求提供 `[any SettingsPage]` 的注册表，这意味着必须使用"协议存在性"
/// （protocol existential），不能引入 associated type Body: View，因为带关联类型的
/// 协议无法直接放进同构数组。
///
/// 替代方案是让 `body` 返回 `AnyView`（已做类型擦除），调用方显式擦除，
/// 而不是通过 @ViewBuilder + some View 的方式。这样协议本身可以直接用作
/// `[any SettingsPage]` 的元素类型，无需再引入额外包装器。
///
/// 详见 ADR: docs/adrs/2026-04-22-settings-page-registry.md
protocol SettingsPage {
    /// 既有 SettingsTab 枚举继续承担 ID 角色，保持与 tab 导航的单一对应关系。
    var id: SettingsTab { get }

    /// 标题键用于 tab bar 和 header 的多语言展示。
    var titleKey: (chinese: String, english: String) { get }

    /// 页面主体，接收当前界面语言并返回类型擦除的视图。
    /// 使用 @MainActor 因为 SwiftUI body 必须在主线程构建。
    @MainActor func body(uiLanguage: AppUILanguage) -> AnyView
}
