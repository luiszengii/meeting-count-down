# 2026-03-30 单一 app target 启动工程骨架

- 状态：Accepted
- 日期：2026-03-30
- 关联日志：[2026-03-30 开发日志](../dev-logs/2026-03-30.md)

## 背景

项目已经完成文档治理和总体架构规划，但还没有任何原生 macOS 工程或 Swift 源码。Phase 0 的目标是先把应用运行壳层、统一会议域模型和后续可扩展的代码树落下来。此时如果过早拆成多 target 或多个 Swift Package，会把本该先验证的“菜单栏应用生命周期、统一状态流、目录边界”复杂化。

## 决策

项目在 Phase 0 采用“单一 macOS app target + 目录分层 + 协议边界”的启动方式：

1. 使用一个原生 macOS SwiftUI app target 作为当前唯一可运行产物。
2. 通过 [project.yml](../../project.yml) 维护工程规格，并生成 [MeetingCountdown.xcodeproj](../../MeetingCountdown.xcodeproj)。
3. 代码根目录固定为 [MeetingCountdownApp](../../MeetingCountdownApp)，先按 `AppShell`、`Domain`、`SourceCoordinator`、`Preferences`、`Diagnostics`、`Shared` 分层。
4. 单元测试固定在 [MeetingCountdownAppTests](../../MeetingCountdownAppTests)，优先覆盖领域规则和协调层状态流。
5. 后续真实接入能力先通过 `MeetingSource` 协议接入，不在 Phase 0 提前拆 Swift Package 或多 framework target。

## 备选方案

### 方案 A：一开始拆成多个 Swift Package

优点是模块边界更硬；缺点是对于菜单栏应用这种高度依赖 macOS 生命周期和 SwiftUI Scene 的工程，启动成本更高，早期很容易为了包边界反复搬运类型。

### 方案 B：一开始拆成多个 Xcode target / framework

优点是更贴近未来发布形态；缺点是需要更早处理 target 依赖、资源、签名和测试宿主，和当前 Phase 0 目标不匹配。

### 方案 C：只建 Swift Package，不建原生 Xcode app 工程

优点是简单；缺点是无法自然承载菜单栏应用、Settings Scene 和未来分发流程，不利于尽早验证真实运行形态。

## 影响

- 工程现在可以直接在 Xcode 中打开并运行最小菜单栏骨架。
- 统一会议域模型和刷新入口已经固定，后续各接入方式必须兼容这些接口。
- 未来如果要抽 Package 或多 target，应在已有目录边界稳定后再做，而不是现在为了形式先拆。

## 后续动作

1. 在 Phase 1 基于现有 `AppShell` 和 `SourceCoordinator` 接入四路接入向导。
2. 逐步用真实的 EventKit、OAuth、导入和 CLI 模块替换当前 stub 数据源。
3. 保持目录级 `AGENTS.md` 与实现同步更新，避免代码树增长后失去可读入口。
