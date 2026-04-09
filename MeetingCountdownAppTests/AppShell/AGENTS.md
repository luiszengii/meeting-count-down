# AGENTS.md

## 模块名称

`MeetingCountdownAppTests/AppShell`

## 模块目的

验证 `AppShell` 里的轻量壳层桥接和场景级约束，确保菜单栏入口、设置窗口打开链路这类容易受 SwiftUI / AppKit 生命周期影响的逻辑不会被后续重构破坏。

## 包含内容

- `SettingsSceneOpenControllerTests.swift`：锁定设置窗口打开桥接器的登记、覆盖和调用语义。

## 关键依赖

- XCTest
- `AppShell`
- SwiftUI 场景桥接约束

## 关键状态 / 数据流

这里的测试通常不覆盖具体视觉渲染，而是验证“菜单栏和 app 菜单登记了什么打开动作、壳层控制器会不会走到统一的设置窗口链路、重复登记时是否还调用最新动作”这类状态和动作流。

## 阅读入口

先看 `SettingsSceneOpenControllerTests.swift`，再回到 [MeetingCountdownApp/AppShell/AGENTS.md](../../MeetingCountdownApp/AppShell/AGENTS.md) 对照真实壳层结构。

## 开发注意事项

- 这类测试优先锁定桥接器语义，不要把 `NSPopover`、`NSStatusItem` 之类重宿主生命周期直接搬进单元测试。
- 如果未来新增更多壳层测试，也继续按“一个场景约束对应一组可读的命名测试”方式组织，并补中文注释说明为什么这个约束重要。
