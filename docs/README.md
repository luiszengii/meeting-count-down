# Docs

项目文档统一放在 `docs/` 下，目标不是堆 Markdown，而是形成可以跨 session 继承的知识网络：你可以从根级 [AGENTS.md](../AGENTS.md) 了解仓库级规则，再从这里进入开发日志、踩坑文、ADR 和模板。

## 导航

| 目录 / 文件 | 作用 | 入口 |
| --- | --- | --- |
| `dev-logs/` | 每日开发推进记录 | [今日日志](./dev-logs/2026-03-31.md) |
| `pitfalls/` | 踩坑记录、排查过程、根因与修复 | [Pitfalls 索引](./pitfalls/README.md) |
| `adrs/` | 技术、产品形态、架构变动记录 | [ADR 索引](./adrs/README.md) |
| `templates/` | 文档模板与复制入口 | [模板索引](./templates/README.md) |

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
- ADR：
  - [建立项目级文档治理系统](./adrs/2026-03-30-documentation-governance.md)
  - [单一 app target 启动工程骨架](./adrs/2026-03-30-single-app-target-bootstrap.md)
  - [强化学习导向的 Swift 注释密度要求](./adrs/2026-03-30-learning-oriented-swift-comment-density.md)
  - [提升最低 macOS 版本到 14](./adrs/2026-03-30-bump-minimum-macos-to-14.md)
  - [CalDAV-only 产品范围收敛](./adrs/2026-03-31-caldav-only-product-scope.md)
- Pitfall：
  - [xcodebuild 首次运行时插件加载失败](./pitfalls/xcodebuild-first-launch-plugin-failure.md)
  - [EventKit 日历权限调试边界](./pitfalls/eventkit-calendar-permission-debugging.md)
  - [SwiftUI Settings scene 在菜单栏 app 里的打开方式](./pitfalls/swiftui-settings-scene-in-menu-bar-app.md)
  - [新增源文件后需要重新生成 Xcode 工程](./pitfalls/xcodegen-regenerate-project-after-adding-files.md)
- 模板：
  - [Daily Log](./templates/dev-log.md)
  - [Pitfall](./templates/pitfall.md)
  - [ADR](./templates/adr.md)
  - [Module AGENTS](./templates/module-agents.md)
