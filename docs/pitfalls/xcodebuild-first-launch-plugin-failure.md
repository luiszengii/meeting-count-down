# xcodebuild-first-launch-plugin-failure

## 现象

首次执行 `xcodebuild test` 时，构建还没有进入源码编译阶段，就直接失败并报出 `IDESimulatorFoundation` 插件加载错误，日志里同时提示应尝试执行 `xcodebuild -runFirstLaunch`。

## 背景

问题出现在本仓库刚完成原生 Xcode 工程初始化之后。此时 [MeetingCountdown.xcodeproj](../../MeetingCountdown.xcodeproj) 已经生成，但本机 Xcode 26.4 的首次启动初始化并没有完全完成。

## 排查过程

1. 先确认失败发生在 `xcodebuild` 启动阶段，而不是 Swift 代码编译阶段。
2. 观察错误日志，发现核心报错集中在 `IDESimulatorFoundation` 与 `DVTDownloads` 的符号缺失。
3. 日志里有明确建议：`A required plugin failed to load`，并提示执行 `xcodebuild -runFirstLaunch`。
4. 执行 `xcodebuild -runFirstLaunch` 后，再次运行 `xcodebuild test`，插件加载错误消失，测试开始进入正常编译和执行流程。

## 根因

不是仓库代码问题，而是本机 Xcode 安装后的首次启动任务未完成，导致 `xcodebuild` 所依赖的系统插件和组件状态不完整。

## 解决方案

执行：

```bash
xcodebuild -runFirstLaunch
```

等安装流程完成后，再重新运行 `xcodebuild test`。

## 预防方式

- 新机器或刚升级 Xcode 后，第一次在仓库里跑构建前，先执行一次 `xcodebuild -runFirstLaunch`。
- 如果再次看到类似 “A required plugin failed to load” 的报错，先优先排查 Xcode 自身初始化状态，不要直接怀疑仓库源码。
- 在开发日志里记录这类工具链级问题，避免后续 session 重复排查。

## 相关链接

- 开发日志：[2026-03-30](../dev-logs/2026-03-30.md)
- ADR：[单一 app target 启动工程骨架](../adrs/2026-03-30-single-app-target-bootstrap.md)
- 相关目录 `AGENTS.md`：[MeetingCountdownApp](../../MeetingCountdownApp/AGENTS.md)
