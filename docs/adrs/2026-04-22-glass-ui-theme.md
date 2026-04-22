# 2026-04-22 提取 GlassUITheme 统一 UI 设计常量

- 状态：Accepted
- 日期：2026-04-22
- 关联日志：暂无

## 背景

审计发现以下问题：

- **M-3**：圆角半径（`cornerRadius`）、内边距（`padding`）等 `CGFloat` 字面量重复散落在 `GlassUI.swift` 的多个视图组件（`GlassPanel`、`GlassCard`、`GlassIconButtonStyle`、`GlassListRowButtonStyle`）中，无统一出处。
- **M-8**：菜单栏弹层尺寸 `NSSize(width: 324, height: 270)`、最大宽度 `220`、胶囊补偿宽度 `12` 等与菜单栏布局相关的尺寸字面量在 `MenuBarStatusItemController.swift` 内硬编码，变更时需要跨文件查找并手动对齐。

重构路线图（refactor-roadmap-2026-04-22.md）将 T1 定为"把上述重复字面量提取进单一设计常量文件"，以减少将来视觉调整时的改动范围。

## 决策

新建 `MeetingCountdownApp/AppShell/GlassUITheme.swift`，以无实例化 `enum` 方式定义三组静态常量命名空间：

- `GlassUITheme.CornerRadius`：覆盖 `large`（22）、`medium`（18）、`extraSmall`（16）、`compact`（12）四个圆角档位。
- `GlassUITheme.Padding`：覆盖 `default`（14）、`compact`（12）两个内边距档位。
- `GlassUITheme.MenuBar`：覆盖 `maxCapsuleStatusItemLength`（220）、`popoverContentSize`（324×270）、`extraWidth`（12）三个菜单栏布局量。

`GlassUI.swift` 和 `MenuBarStatusItemController.swift` 中对应的字面量全部替换为符号引用，不改变任何行为或布局结构。

## 备选方案

### 方案 A：直接在各组件内保留字面量，只加注释说明值含义

没有采用。注释无法在编译期约束一致性，将来改值仍需逐文件搜索，无法解决 M-3 / M-8 的根因。

### 方案 B：用 struct 或 class 而非无实例化 enum 承载常量

没有采用。Swift 的无实例化 `enum` 是社区惯用的"不可实例化命名空间"模式，比 `final class` / `struct` 更明确地表达"这里没有状态，只有常量"。

### 方案 C：使用 SwiftUI `EnvironmentKey` 注入主题值

没有采用。当前设计系统的常量都是固定值（不随用户偏好变化），引入环境注入会增加传播路径，收益远小于成本。

## 影响

- 新增一个文件（`GlassUITheme.swift`），对 `GlassUI.swift` 和 `MenuBarStatusItemController.swift` 仅做字面量替换，外部行为零变化。
- 将来调整任意设计值只需编辑 `GlassUITheme.swift`，不再需要跨多文件查找。
- 未来新增组件可直接引用已有常量，避免再次引入新的硬编码字面量。

## 后续动作

1. T2 完成后，检查 `SettingsView.swift` 及 `Settings/` 子目录中是否存在与上述常量重叠的字面量，视情况在后续 ADR 中决策是否统一引用 `GlassUITheme`。
2. 如未来引入动态主题或暗色/亮色分支，可以将 `GlassUITheme` 扩展为协议或环境键方案，本次 ADR 不预设该演进路径。
