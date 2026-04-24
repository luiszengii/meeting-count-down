# swift-version-divergence-local-vs-ci

## 现象

本地 `xcodebuild build` 与 `xcodebuild test` 全部通过，但同样的 commit push 到 GitHub 后 CI 全 fail。typical 错误：

```
error: call to main actor-isolated initializer 'init(wrappedValue:)' in a synchronous nonisolated context
    @ObservedObject var soundProfileLibraryController: SoundProfileLibraryController

error: 'isolated' deinit requires frontend flag -enable-experimental-feature IsolatedDeinit
    nonisolated deinit {
```

误以为是 CI 配置出了问题、或代码刚 push 完没及时同步——实际是本地 Swift 工具链版本比 CI 新一截，新版本对若干 `@MainActor` / Sendable / 并发 deinit 规则**比 CI 更宽松**，导致同一段代码本地编译通过、CI 编译失败。

## 背景

项目 `project.yml` 写的是 `SWIFT_VERSION: 6.0`，但 `SWIFT_VERSION` 只控制语言模式，不控制工具链。实际工具链版本由本机 / CI runner 上安装的 Xcode 决定。

- 作者机器：macOS 26 + Xcode beta + **Swift 6.3.1** (`swiftlang-6.3.1.1.2`)
- CI macos-15 runner：默认 Xcode 16 + **Swift 6.0** / **6.1**（取决于 runner image 当前小版本）

Swift 6.x 的严格并发规则在每个小版本都在演化，6.3 对若干 case 的诊断比 6.0 更宽松（典型例：`@ObservedObject` 持有 `@MainActor`-isolated 类型时，6.3 隐式推断 enclosing struct 为 `@MainActor`，6.0 强制要求显式标注）。

只要本地工具链领先 CI 一两个小版本，"本地 build 过 = CI 也过"就不成立。

## 排查过程

1. **第一波误判**：以为是网络问题，因为 `gh` CLI 报 `LibreSSL SSL_connect: SSL_ERROR_SYSCALL`。重试后 `gh run list` 拿到结果才发现 CI 实际从 `831e6e8` (W6 T20+T21) 起就一直在红，连用户自己的 `v0.1.5` push 也是红的——所有人都没看 CI。
2. **看 CI log**：定位到两类错误：5 处 `@ObservedObject init(wrappedValue:)` nonisolated context；1 处 `nonisolated deinit` 要 `-enable-experimental-feature IsolatedDeinit`。
3. **本地复现**：本地 `xcodebuild` 跑同一份代码 `BUILD SUCCEEDED`、`TEST SUCCEEDED 106/106`。差异不是代码而是工具链。
4. **确认工具链版本**：`swift -version` 报 `Apple Swift 6.3.1 (swiftlang-6.3.1.1.2)`；CI runner 默认 Xcode 16 报 Swift 6.0。

## 根因

Swift 6.0 严格并发要求：

- `@ObservedObject` 的 `init(wrappedValue:)` 是 `@MainActor`-isolated（因为 `ObservableObject` 通常是 main actor 类型）。在 nonisolated 上下文调用它会报错。
- 持有 `@ObservedObject` 属性的 struct 必须自身是 `@MainActor`（或显式标记），否则属性默认初始化器跑在 nonisolated 上下文。

Swift 6.3 在这条规则上做了**隐式推断**——struct 持有 `@MainActor`-isolated 类型属性时自动视为 `@MainActor`，不需要显式标注。这就是本地不报错、CI 报错的根本差异。

`nonisolated deinit` 是 Swift 6.1 引入的实验性语法，要 `-enable-experimental-feature IsolatedDeinit` 启用。Swift 6.0 直接拒绝该语法。但 6.3 默认接受。

## 解决方案

两条修法（commit `f9361e6`）：

1. **`SettingsPage` 协议加 `@MainActor`**——所有 conforming page struct 自动继承 `@MainActor`，5 处 `@ObservedObject` 属性的初始化都跑在 main actor 上。

   ```swift
   @MainActor
   protocol SettingsPage {
       var id: SettingsTab { get }
       var titleKey: (chinese: String, english: String) { get }
       func body(uiLanguage: AppUILanguage) -> AnyView
   }
   ```

2. **`ReminderEngine.deinit` 去掉 `nonisolated` 关键字**——普通 `deinit` 在 `@MainActor` 类型上**默认就是 nonisolated**，访问 `nonisolated(unsafe) var _hasActiveScheduledTask` 完全合法，不需要任何 Swift 6.1 实验性 feature。

   ```swift
   // 不要写 `nonisolated deinit { ... }`
   deinit {
       if _hasActiveScheduledTask {
           assertionFailure("...")
       }
   }
   ```

## 预防方式

- **push 后必须看 CI 状态再继续工作**：本地 build/test 过只是必要条件，不是 ship 信号。这条规则需要写进 [AGENTS.md](../../AGENTS.md) 的 AI 代理执行约束。
- **遇到 Swift 6.x 严格并发新语法（`nonisolated deinit`、`isolated` 关键字、新的 actor 隔离推断），先 check Swift release notes 看哪个版本起稳定**。CI 的工具链版本是兼容下限，不是上限。
- **CI workflow 显式锁定 Xcode 版本**（用 `xcode-select -p` + `Install Xcode` step），避免 GitHub runner image 升级时静默引入新行为。当前 [tests.yml](../../.github/workflows/tests.yml) 用的是 `macos-15` 默认 Xcode，未来如果遇到 runner 默认 Xcode 升级带来的破坏，可以在 workflow 加 `sudo xcode-select -s /Applications/Xcode_16.4.app` 这种锁版本步骤。
- **不要用 Swift 实验性 feature 去解决普通问题**——`nonisolated deinit` 当时是为了"显式声明意图"，但普通 `deinit` 已经能解决一切，引入实验语法只是制造工具链兼容陷阱。

## 相关链接

- 开发日志：[2026-04-24](../dev-logs/2026-04-24.md)
- ADR：暂无
- 相关目录 `AGENTS.md`：[根 AGENTS](../../AGENTS.md)、[.github/workflows/AGENTS](../../.github/workflows/AGENTS.md)
