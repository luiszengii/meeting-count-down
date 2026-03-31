# xcodegen-regenerate-project-after-adding-files

## 现象

- 磁盘上已经新建了 `.swift` 文件，代码里也已经开始引用这个新类型，但 `xcodebuild` 仍然报 `cannot find type ... in scope`。
- 看起来像 Swift 编译器找不到定义，实际上新文件根本没有进 target。

## 背景

本仓库的 Xcode 工程由 [project.yml](../../project.yml) 生成并提交到仓库中。日常开发虽然直接编辑 `.swift` 文件即可，但“新增、删除、重命名文件”不会自动更新已经存在的 `.xcodeproj`。

## 排查过程

1. 新增 [SettingsWindowController.swift](../../MeetingCountdownApp/AppShell/SettingsWindowController.swift) 后，`AppRuntime` 等文件开始引用 `SettingsWindowController`。
2. 首次执行 `xcodebuild test` 时，编译器直接报 `cannot find type 'SettingsWindowController' in scope`。
3. 回看 `swift-frontend` 的编译文件列表，发现新文件并没有出现在当前 target 的源码输入里。
4. 这时问题不再是 Swift 语法，而是工程文件仍然停留在旧状态。
5. 执行 `xcodegen generate` 重新生成 [MeetingCountdown.xcodeproj](../../MeetingCountdown.xcodeproj) 后，再次构建通过。

## 根因

仓库使用的是“`project.yml` 作为真实声明源，`.xcodeproj` 作为生成产物”的工作方式。新增源文件后，如果不重新生成工程，Xcode / `xcodebuild` 仍然会按旧的文件清单编译。

## 解决方案

在新增、删除或重命名源文件后，执行：

```bash
xcodegen generate
```

然后再运行 `xcodebuild test` 或在 Xcode 里继续开发。

## 预防方式

- 只要这次改动涉及文件结构变化，而不只是编辑现有文件，就把 `xcodegen generate` 当成固定步骤。
- 遇到 “文件明明在磁盘上，但编译器说找不到类型” 时，先检查工程是否过期，不要立刻怀疑 Swift 可见性或模块导入。
- 开发日志和 Pitfall 文档里持续强调：`project.yml` 才是源头，`.xcodeproj` 需要再生成。

## 相关链接

- 开发日志：[2026-03-31](../dev-logs/2026-03-31.md)
- ADR：[2026-03-30 单一 app target 启动工程骨架](../adrs/2026-03-30-single-app-target-bootstrap.md)
- 相关目录 `AGENTS.md`：[MeetingCountdownApp](../../MeetingCountdownApp/AGENTS.md)
