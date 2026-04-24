# 2026-04-23 引入 swift-snapshot-testing 进行视觉回归测试

- 状态：Accepted
- 日期：2026-04-23
- 关联日志：暂无

## 背景

T10（快照框架采用）在 refactor-roadmap-2026-04-22 中被标记为"已延迟，待用户决策"。
核心顾虑是：当前项目零外部依赖，审计视之为优势——引入第一个外部 Swift Package
需要用户明确同意，并清楚地记录理由。

用户于 2026-04-24 明确批准接入快照框架，理由是：

1. SettingsPage 注册表已在 W5 落地，5 个页面的结构性测试覆盖了"构建不崩溃"，
   但没有视觉层面的回归兜底。任何 UI 改动都可能在无感知中破坏布局。
2. MenuBarContentView 是用户每次打开弹层时都能看到的核心 UI，尚无自动化视觉覆盖。
3. `MenuBarPresentationCalculator` 已有 17 条单元测试，不再需要快照；
   NSStatusItem 本身属于 AppKit 层，与系统环境耦合深，不适合快照（见下方"不快照"决策）。

## 决策

1. **选择 swift-snapshot-testing v1.19.2（MIT 免费许可证）**
   - Point-Free 出品，社区广泛使用，macOS 原生支持，不依赖 Apple Developer Program。
   - 依赖版本锁为 `.upToNextMinor(from: "1.19.2")` 以保守跟进补丁。

2. **覆盖范围**
   - 5 个 SettingsPage（Overview / Calendar / Reminders / Audio / Advanced）× 2 模式（亮 / 暗）= 10 条快照测试。
   - MenuBarContentView 3 种代表性状态（空闲、会议倒计时中、数据源错误）= 3 条快照测试。
   - 合计 13 条快照测试，全部以亮/暗模式 PNG 存入 `__Snapshots__` 目录。

3. **不快照 NSStatusItem 本身**
   - NSStatusItem 属于 AppKit 宿主层，依赖真实菜单栏环境，在 headless xcodebuild 中无法稳定渲染。
   - MenuBarPresentationCalculator 已有完整单元测试覆盖其逻辑，无需再叠加快照。

4. **技术实现细节**
   - macOS 上 SnapshotTesting 没有 SwiftUI 直接策略（该策略仅支持 iOS/tvOS），
     通过 `NSHostingController` 桥接后使用 `NSViewController.image(size:)` 策略。
   - 亮/暗模式通过 `NSView.appearance` 切换，不依赖系统全局外观设置。
   - Swift 6 + xcodebuild 下 `#file` 可能产生相对路径，导致快照写入失败；
     通过 `verifySnapshot(snapshotDirectory:)` 传入 `#filePath` 派生的绝对路径解决。
   - `Package.resolved` 存放在 `MeetingCountdown.xcodeproj/.../swiftpm/Package.resolved`，
     需要从 `.gitignore` 中排除并入库，以确保依赖版本在 CI 和本地构建中一致。

## 备选方案

### 方案 A：XCUITest
未采用。XCUITest 需要启动完整的 UI 环境，运行慢（通常 10–60 倍于单元测试），
且在当前 headless CI 配置（无签名、无 Developer Program）下可靠性低。

### 方案 B：自己写视图等价比对
未采用。需要重新实现图像序列化、哈希比对和差异可视化，属于重复造轮子。
swift-snapshot-testing 已经提供了这一切，且有成熟的 image diff 支持。

## 影响

- 这是项目的**第一个外部 Swift Package 依赖**，打破了零依赖的历史记录。
  但 swift-snapshot-testing 是测试专属依赖（仅加入测试目标），不影响生产包大小。
- CI SPM resolve 时间增加约 30 秒（首次；后续缓存后可忽略不计）。
- 13 张 PNG 基线图（合计约 2–5 MB）进入 repo；PR 中 UI 改动会附带 diff 图片。
- 未来 Xcode 大版本升级时，需确认 swift-snapshot-testing 的 swift-syntax 依赖
  与新 Xcode 的 Swift 编译器版本兼容。

## 后续动作

- 基线录入后，任何 UI 改动若导致像素级变化，本地测试会失败并报告 diff 图片。
- 如果改动是预期的（例如刻意调整布局），需要手动重录基线：
  `withSnapshotTesting(record: .all) { super.invokeTest() }` 或删除旧 PNG 后重新运行测试。
- 后续可扩展覆盖英文界面模式快照，当前暂只覆盖中文（简体）。

## 状态更新（2026-04-24）：CI 跳过快照测试

第一次把 13 条快照测试推到 CI 后，全部 fail——baseline 在作者本地（macOS 26 + Xcode beta）录制，CI macos-15 runner 用的是 macOS 15 + Xcode 16，**字体渲染、HiDPI 缩放和 AppKit 渲染管线版本与本地不同，PNG 像素级对比必然产生差异**，即使代码完全没改。

详细分析见 [pitfall: snapshot-pixel-diff-cross-environment](../pitfalls/snapshot-pixel-diff-cross-environment.md)。

### 决定

[`.github/workflows/tests.yml`](../../.github/workflows/tests.yml) 在 `xcodebuild test` 命令上加：

```bash
-skip-testing:FeishuMeetingCountdownTests/MenuBarContentViewSnapshotTests
-skip-testing:FeishuMeetingCountdownTests/SettingsPageSnapshotTests
```

CI 测试规模 106 → 93。**本地仍跑全部 106 含快照**。

### 取舍

- 快照测试的真正价值是"作者本地写代码时 catch UI 退化"，CI 跑像素对比是 anti-pattern。
- 没有引入 `precision: 0.95 / perceptualPrecision: 0.95` 容差选项——容差有掩盖真回归的风险，本地仍然走严格对比更直接。
- 没有把 CI 改成"baseline 唯一权威源"——这要求作者本地不录基线（只 run），并通过 artifact 流程拿 baseline，工作流复杂度跳一档；当前作者机器单源足够。

### 何时回头评估

- 如果团队规模超过 1 人，作者机器不再是唯一录制源，需重新设计 baseline 权威源策略。
- 如果出现"本地没注意到 UI 退化但被用户发现"的 case，说明本地快照保护不够，需要补 CI 的视觉守护。
