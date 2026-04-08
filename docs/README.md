# Docs

项目文档统一放在 `docs/` 下，目标不是堆 Markdown，而是形成可以跨 session 继承的知识网络：你可以从根级 [AGENTS.md](../AGENTS.md) 了解仓库级规则，再从这里进入开发日志、踩坑文、ADR 和模板。

## 导航

| 目录 / 文件 | 作用 | 入口 |
| --- | --- | --- |
| `dev-logs/` | 每日开发推进记录 | [今日日志](./dev-logs/2026-04-03.md) |
| `pitfalls/` | 踩坑记录、排查过程、根因与修复 | [Pitfalls 索引](./pitfalls/README.md) |
| `adrs/` | 技术、产品形态、架构变动记录 | [ADR 索引](./adrs/README.md) |
| `manual-installation.md` | 手动分发测试版的安装与首次打开放行说明 | [手动安装说明](./manual-installation.md) |
| `templates/` | 文档模板与复制入口 | [模板索引](./templates/README.md) |

## 当前进度快照

- `Phase 0 ~ 5` 已完成：CalDAV-only 收敛、系统日历桥接、下一场会议选择、本地提醒引擎、提醒音频库、菜单栏倒计时与闪烁、刷新策略、同步新鲜度提示和开机启动都已经接入运行时。
- 当前阶段是 `Phase 6`：重点先转向无会员前提下的手动分发准备，包括 `Release` 构建、`.app` / `.zip` / `.dmg` 导出、首次打开放行说明和用户接入文档。
- 如果测试目标包含“另一台 macOS 机器上的 Calendar / EventKit 权限”，当前阶段不能只用 unsigned 安装包下结论；详见 [unsigned DMG 在另一台 Mac 上无法稳定承接 Calendar 权限](./pitfalls/unsigned-dmg-calendar-permission-on-other-mac.md)。
- `Developer ID` 签名、notarization、DMG / Sparkle 自动更新暂时不再作为当前阻塞项，详见 [2026-04-02 Phase 6 先转为无会员手动分发](./adrs/2026-04-02-phase-6-manual-distribution-without-paid-membership.md)。
- 最近一次壳层回归修复集中在菜单栏 `Settings` scene 的官方打开路径，详见 [2026-04-02 开发日志](./dev-logs/2026-04-02.md) 和 [SwiftUI Settings scene 在菜单栏 app 里的打开方式](./pitfalls/swiftui-settings-scene-in-menu-bar-app.md)。

## 使用规则

1. 有当天推进，就更新当天日志，不新建多份同日文件。
2. 有反复排查的问题，就写进 `pitfalls/`，并从当天日志链接过去。
3. 有技术路线、产品形态、文档规则或架构决策变化，就新增 ADR。
4. 所有文档默认使用相对路径链接，能回链就尽量回链。
5. 未来任何新增代码目录，都先补该目录自己的 `AGENTS.md`，再补代码。

## 命名约定

| 类型 | 命名方式 |
| --- | --- |
| 每日日志 | `YYYY-MM-DD.md` |
| ADR | `YYYY-MM-DD-kebab-case-title.md` |
| Pitfall | `kebab-case-title.md` |
| 目录级索引 | `AGENTS.md` |

## 当前文档网络

- 开发日志：[2026-03-30](./dev-logs/2026-03-30.md)
- 开发日志：[2026-03-31](./dev-logs/2026-03-31.md)
- 开发日志：[2026-04-01](./dev-logs/2026-04-01.md)
- 开发日志：[2026-04-02](./dev-logs/2026-04-02.md)
- ADR：
  - [建立项目级文档治理系统](./adrs/2026-03-30-documentation-governance.md)
  - [单一 app target 启动工程骨架](./adrs/2026-03-30-single-app-target-bootstrap.md)
  - [强化学习导向的 Swift 注释密度要求](./adrs/2026-03-30-learning-oriented-swift-comment-density.md)
  - [提升最低 macOS 版本到 14](./adrs/2026-03-30-bump-minimum-macos-to-14.md)
  - [CalDAV-only 产品范围收敛](./adrs/2026-03-31-caldav-only-product-scope.md)
- Pitfall：
  - [xcodebuild 首次运行时插件加载失败](./pitfalls/xcodebuild-first-launch-plugin-failure.md)
  - [EventKit 日历权限调试边界](./pitfalls/eventkit-calendar-permission-debugging.md)
  - [unsigned DMG 在另一台 Mac 上无法稳定承接 Calendar 权限](./pitfalls/unsigned-dmg-calendar-permission-on-other-mac.md)
  - [SwiftUI Settings scene 在菜单栏 app 里的打开方式](./pitfalls/swiftui-settings-scene-in-menu-bar-app.md)
  - [新增源文件后需要重新生成 Xcode 工程](./pitfalls/xcodegen-regenerate-project-after-adding-files.md)
- 模板：
  - [Daily Log](./templates/dev-log.md)
  - [Pitfall](./templates/pitfall.md)
  - [ADR](./templates/adr.md)
  - [Module AGENTS](./templates/module-agents.md)
