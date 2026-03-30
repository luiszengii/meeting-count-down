# 2026-03-30 提升最低 macOS 版本到 14

- 状态：Accepted
- 日期：2026-03-30
- 关联日志：[2026-03-30 开发日志](../dev-logs/2026-03-30.md)

## 背景

Phase 0 的菜单栏应用已经跑起来，但设置入口为了兼容 `macOS 13` 被迫绕开 `SettingsLink`，改成了手动发送 AppKit action。实际运行时系统明确报错要求使用 `SettingsLink` 打开设置场景，这说明当前实现既不优雅，也没有遵循 SwiftUI 的推荐路径。

## 决策

项目最低支持版本从 `macOS 13` 提升到 `macOS 14`：

1. `project.yml` 的 `MACOSX_DEPLOYMENT_TARGET` 和所有 target 的 `deploymentTarget` 统一改为 `14.0`。
2. 菜单栏中的“打开设置”恢复使用 SwiftUI 原生 `SettingsLink`。
3. 文档中的平台支持说明同步更新为“macOS 14 及以上”。

## 备选方案

### 方案 A：继续支持 macOS 13，并保留 AppKit 绕行方案

优点是覆盖更老系统；缺点是设置入口行为和 SwiftUI Scene 机制不一致，而且已经出现系统级报错提示，不值得为首版继续背这层兼容性负担。

### 方案 B：直接把最低版本拉到更高，例如 macOS 15 或当前 SDK 主版本

优点是能更激进使用新 API；缺点是当前问题只需要 `macOS 14` 就能解决，没有必要进一步缩小可安装范围。

## 影响

- 设置窗口入口将回到系统推荐实现，行为更稳定。
- `xcodebuild test` 中与 XCTest 最低版本不一致相关的 warning 会减少或消失。
- 首版不再面向 `macOS 13 Ventura` 用户。

## 后续动作

1. 后续 SwiftUI 设置页和接入向导默认以 `macOS 14+` API 为基础设计。
2. 如果未来出现必须依赖 `macOS 15+` 的系统能力，再单独记录版本提升 ADR。
