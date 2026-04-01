# swiftui-menubarextra-timelineview-overdraw

## 现象

给 `MenuBarExtra` 的 label 直接塞 `TimelineView(.periodic(...))` 后，单元测试宿主 app 会长时间不退出，`xcodebuild test` 看起来像卡死。对运行中的 app 做采样时，会看到主线程大量停留在 `MenuBarExtraController.updateButton(_:)` 和 SF Symbols 图片重建路径里。

## 背景

问题出现在 `MeetingCountdownApp/AppShell/MenuBarContentView.swift` 对菜单栏标签做“闪烁提醒”尝试时。为了在提醒命中时做动画，曾把菜单栏 label 改成基于 `TimelineView` 的周期性切换图标/标题。

## 排查过程

1. 先确认不是测试本身失败。编译已经通过，但 `xcodebuild test` 长时间没有结束。
2. 检查进程发现测试宿主 app 仍在运行，说明更像是 host app 生命周期或 UI 刷新问题，而不是 XCTest 断言失败。
3. 对宿主 app 采样后，主线程大部分时间都卡在 `MenuBarExtraController.updateButton(_:) -> NSStatusBarButton setImage:` 这条链路，说明问题集中在菜单栏按钮的高频重绘。
4. 去掉 `TimelineView`，改成只在提醒状态真正变化时静态切换标签后，测试立即恢复正常。

## 根因

`MenuBarExtra` 的 label 适合承载轻量、低频更新的状态展示，但不适合直接挂一个持续驱动的 `TimelineView` 做动画。周期性更新会频繁触发菜单栏按钮重绘和 SF Symbols 重新解析，在菜单栏 app 宿主环境里很容易把 UI 更新放大成明显性能问题，甚至拖慢测试进程退出。

## 解决方案

当前采用“静态高亮而不是持续动画”：

1. 平时菜单栏继续显示下一场会议倒计时。
2. 当提醒真正命中时，只把菜单栏标题/图标切换为更显眼的提醒态。
3. 不再在 `MenuBarExtra` label 内部使用 `TimelineView` 或其他持续时钟驱动视图。

这样依然能给用户一个可见提醒，同时保持菜单栏宿主稳定。

## 预防方式

- 给 `MenuBarExtra` 做视觉增强时，优先用“状态切换”而不是“持续动画”。
- 如果未来一定要做动画，先验证测试宿主和真实运行态的 CPU / 内存行为，再决定是否保留。
- 看到 `xcodebuild test` 无明显错误却长时间不退出时，优先怀疑菜单栏宿主 app 本身被 UI 重绘拖住。

## 相关链接

- 开发日志：[2026-04-01](../dev-logs/2026-04-01.md)
- ADR：
- 相关目录 `AGENTS.md`：[AppShell](../../MeetingCountdownApp/AppShell/AGENTS.md)
