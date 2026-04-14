# Global Index

这份文档是项目的“内容导向总索引”。它和 [README](../README.md)、[Docs 总览](./README.md)、[dev-logs](./dev-logs/README.md) 的分工不同：

- [README](../README.md) 负责给新进入仓库的人一个产品和工程入口。
- [Docs 总览](./README.md) 负责解释文档系统怎么用、当前重点在哪里。
- [开发日志](./dev-logs/README.md) 负责按时间记录发生了什么。
- 本页负责按内容类型把当前项目计划内的正式文档集中列出来，尽量避免“文档存在，但没有一个全局入口能找到它”。

这页不追求长篇说明，只追求“知道有什么、在哪里、为什么存在”。新增、移动或归档正式文档时，应同步更新本页。由 GSD / review skill 生成的旁路工件，不默认纳入这里的正式目录；边界说明见 [Tooling Artifacts](./tooling-artifacts.md)。

## 仓库入口文档

| 文档 | 作用 |
| --- | --- |
| [../README.md](../README.md) | 项目产品入口、当前阶段、运行路径和分发说明的总入口 |
| [../AGENTS.md](../AGENTS.md) | 仓库级长期规则、文档治理规则、模块边界和开发约束 |
| [./README.md](./README.md) | `docs/` 目录的高层导航和当前重点摘要 |
| [./index.md](./index.md) | 当前这份全局内容索引 |
| [./tooling-artifacts.md](./tooling-artifacts.md) | 说明正式文档与工具产物的边界 |
| [./manual-installation.md](./manual-installation.md) | 面向测试用户和维护者的手动安装、放行和导出说明 |

## 文档子索引

| 文档 | 作用 |
| --- | --- |
| [./adrs/README.md](./adrs/README.md) | ADR 列表入口 |
| [./dev-logs/README.md](./dev-logs/README.md) | 每日日志列表入口 |
| [./pitfalls/README.md](./pitfalls/README.md) | Pitfall 列表入口 |
| [./templates/README.md](./templates/README.md) | 文档模板入口 |

## ADR

| 文档 | 作用 |
| --- | --- |
| [./adrs/2026-03-30-documentation-governance.md](./adrs/2026-03-30-documentation-governance.md) | 定义项目级文档治理和文档先行原则 |
| [./adrs/2026-03-30-single-app-target-bootstrap.md](./adrs/2026-03-30-single-app-target-bootstrap.md) | 记录单一 macOS app target 工程骨架的建立 |
| [./adrs/2026-03-30-learning-oriented-swift-comment-density.md](./adrs/2026-03-30-learning-oriented-swift-comment-density.md) | 固化学习导向的 Swift 注释密度要求 |
| [./adrs/2026-03-30-bump-minimum-macos-to-14.md](./adrs/2026-03-30-bump-minimum-macos-to-14.md) | 把最低支持系统提升到 macOS 14 |
| [./adrs/2026-03-30-onboarding-routes-through-settings-window.md](./adrs/2026-03-30-onboarding-routes-through-settings-window.md) | 记录首阶段接入向导先落在设置页的决策 |
| [./adrs/2026-03-31-caldav-only-product-scope.md](./adrs/2026-03-31-caldav-only-product-scope.md) | 产品范围正式收敛到 CalDAV-only 单一路线 |
| [./adrs/2026-04-02-phase-6-manual-distribution-without-paid-membership.md](./adrs/2026-04-02-phase-6-manual-distribution-without-paid-membership.md) | `Phase 6` 暂不阻塞于付费会员，先做无会员手动分发 |

## 开发日志

| 文档 | 作用 |
| --- | --- |
| [./dev-logs/2026-03-30.md](./dev-logs/2026-03-30.md) | 文档系统与 `Phase 0` 工程骨架初始化 |
| [./dev-logs/2026-03-31.md](./dev-logs/2026-03-31.md) | CalDAV-only 范围收敛与 EventKit 权限链路补齐 |
| [./dev-logs/2026-04-01.md](./dev-logs/2026-04-01.md) | `Phase 4` 本地提醒引擎主体落地 |
| [./dev-logs/2026-04-02.md](./dev-logs/2026-04-02.md) | 秒级倒计时、闪烁提醒态、Settings 打开链路和 `Phase 6` 方向调整 |
| [./dev-logs/2026-04-03.md](./dev-logs/2026-04-03.md) | DMG 打包、签名前提澄清、App 图标补齐和第一轮 UI 重构 |
| [./dev-logs/2026-04-08.md](./dev-logs/2026-04-08.md) | 参考 Karpathy 的 LLM Wiki 思路，为项目文档系统补全全局内容索引 |
| [./dev-logs/2026-04-09.md](./dev-logs/2026-04-09.md) | 修正焦点蓝框、收紧 Overview / Audio 信息结构，并补克制微动效 |
| [./dev-logs/2026-04-10.md](./dev-logs/2026-04-10.md) | 拆分 SettingsView 大文件，降低设置页后续维护成本 |
| [./dev-logs/2026-04-12.md](./dev-logs/2026-04-12.md) | 落地 GitHub Release 发布脚本、tag 自动发布 workflow 与签名 secrets 接入 |
| [./dev-logs/2026-04-13.md](./dev-logs/2026-04-13.md) | 修复 keychain 自动探测并完成 GitHub Release 签名 secrets 的真实配置 |
| [./dev-logs/2026-04-14.md](./dev-logs/2026-04-14.md) | 收敛提醒 tab 的状态摘要、时间参数和音频页入口职责 |

## Pitfalls

| 文档 | 作用 |
| --- | --- |
| [./pitfalls/xcodebuild-first-launch-plugin-failure.md](./pitfalls/xcodebuild-first-launch-plugin-failure.md) | 记录 `xcodebuild` 首次运行时插件加载失败的处理 |
| [./pitfalls/eventkit-calendar-permission-debugging.md](./pitfalls/eventkit-calendar-permission-debugging.md) | 记录 EventKit 日历权限与 `Info.plist` 描述的排查边界 |
| [./pitfalls/swiftui-menubarextra-timelineview-overdraw.md](./pitfalls/swiftui-menubarextra-timelineview-overdraw.md) | 记录 `MenuBarExtra` + `TimelineView` 高频重绘问题 |
| [./pitfalls/swiftui-settings-scene-in-menu-bar-app.md](./pitfalls/swiftui-settings-scene-in-menu-bar-app.md) | 记录菜单栏 app 中 SwiftUI `Settings` scene 的正确打开方式 |
| [./pitfalls/xcodegen-regenerate-project-after-adding-files.md](./pitfalls/xcodegen-regenerate-project-after-adding-files.md) | 记录新增源文件后必须重新生成 Xcode 工程 |
| [./pitfalls/unsigned-dmg-calendar-permission-on-other-mac.md](./pitfalls/unsigned-dmg-calendar-permission-on-other-mac.md) | 记录 unsigned DMG 在另一台 Mac 上承接 Calendar 权限失败的根因 |
| [./pitfalls/local-self-signed-code-signing-identity-for-manual-distribution.md](./pitfalls/local-self-signed-code-signing-identity-for-manual-distribution.md) | 记录维护者如何准备本地自签名代码签名身份并接给分发脚本 |
| [./pitfalls/shared-bundle-id-between-debug-and-release-confuses-calendar-permission.md](./pitfalls/shared-bundle-id-between-debug-and-release-confuses-calendar-permission.md) | 记录 Debug / Release 共用 bundle id 时，TCC / EventKit 权限会混淆的问题 |
| [./pitfalls/generated-infoplist-missing-calendar-usage-description-on-release-runner.md](./pitfalls/generated-infoplist-missing-calendar-usage-description-on-release-runner.md) | 记录自动生成 `Info.plist` 在 release runner 上丢失 Calendar 权限说明的问题 |

## 模板

| 文档 | 作用 |
| --- | --- |
| [./templates/dev-log.md](./templates/dev-log.md) | 每日日志模板 |
| [./templates/pitfall.md](./templates/pitfall.md) | Pitfall 模板 |
| [./templates/adr.md](./templates/adr.md) | ADR 模板 |
| [./templates/module-agents.md](./templates/module-agents.md) | 目录级 `AGENTS.md` 模板 |

## 模块级 AGENTS

| 文档 | 作用 |
| --- | --- |
| [../MeetingCountdownApp/AGENTS.md](../MeetingCountdownApp/AGENTS.md) | App 源码总模块边界和阅读入口 |
| [../MeetingCountdownApp/AppShell/AGENTS.md](../MeetingCountdownApp/AppShell/AGENTS.md) | 菜单栏壳层、设置窗口和依赖装配说明 |
| [../MeetingCountdownApp/Diagnostics/AGENTS.md](../MeetingCountdownApp/Diagnostics/AGENTS.md) | 诊断检查与状态模型说明 |
| [../MeetingCountdownApp/Domain/AGENTS.md](../MeetingCountdownApp/Domain/AGENTS.md) | 统一会议模型和领域抽象说明 |
| [../MeetingCountdownApp/OnboardingRouter/AGENTS.md](../MeetingCountdownApp/OnboardingRouter/AGENTS.md) | 首启引导边界占位说明 |
| [../MeetingCountdownApp/Preferences/AGENTS.md](../MeetingCountdownApp/Preferences/AGENTS.md) | 用户偏好与本地持久化说明 |
| [../MeetingCountdownApp/ReminderEngine/AGENTS.md](../MeetingCountdownApp/ReminderEngine/AGENTS.md) | 提醒调度状态机说明 |
| [../MeetingCountdownApp/Shared/AGENTS.md](../MeetingCountdownApp/Shared/AGENTS.md) | 跨模块共享基础设施说明 |
| [../MeetingCountdownApp/SourceCoordinator/AGENTS.md](../MeetingCountdownApp/SourceCoordinator/AGENTS.md) | 数据源聚合与刷新调度说明 |
| [../MeetingCountdownApp/SystemCalendarBridge/AGENTS.md](../MeetingCountdownApp/SystemCalendarBridge/AGENTS.md) | EventKit 系统日历桥接说明 |
| [../MeetingCountdownAppTests/AGENTS.md](../MeetingCountdownAppTests/AGENTS.md) | 测试目录总入口 |
| [../MeetingCountdownAppTests/AppShell/AGENTS.md](../MeetingCountdownAppTests/AppShell/AGENTS.md) | 壳层测试边界说明 |
| [../MeetingCountdownAppTests/Diagnostics/AGENTS.md](../MeetingCountdownAppTests/Diagnostics/AGENTS.md) | 诊断测试边界说明 |
| [../MeetingCountdownAppTests/Domain/AGENTS.md](../MeetingCountdownAppTests/Domain/AGENTS.md) | 领域测试边界说明 |
| [../MeetingCountdownAppTests/Preferences/AGENTS.md](../MeetingCountdownAppTests/Preferences/AGENTS.md) | 偏好测试边界说明 |
| [../MeetingCountdownAppTests/ReminderEngine/AGENTS.md](../MeetingCountdownAppTests/ReminderEngine/AGENTS.md) | 提醒引擎测试边界说明 |
| [../MeetingCountdownAppTests/SourceCoordinator/AGENTS.md](../MeetingCountdownAppTests/SourceCoordinator/AGENTS.md) | 协调层测试边界说明 |
| [../MeetingCountdownAppTests/SystemCalendarBridge/AGENTS.md](../MeetingCountdownAppTests/SystemCalendarBridge/AGENTS.md) | 系统日历桥接测试边界说明 |
| [../.github/AGENTS.md](../.github/AGENTS.md) | GitHub 平台配置与 Release 自动化入口说明 |
| [../.github/workflows/AGENTS.md](../.github/workflows/AGENTS.md) | GitHub Actions workflow 触发与 secrets 约定说明 |
| [../scripts/AGENTS.md](../scripts/AGENTS.md) | 分发与导出脚本说明 |
