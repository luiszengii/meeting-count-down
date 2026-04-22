# Refactor Roadmap — 2026-04-22

> 来源：2026-04-22 `/inspect` 多子代理审计 + 后续 batch 修复
> 状态：本文件是工具产物（参考 `docs/tooling-artifacts.md` 边界），不进 `docs/index.md`
> 已在 batch 修复阶段落地的项见末尾「Already Shipped」。

每个任务前面的 **【Audit-ID】** 对应原审计 finding，**Size**：S=半天 / M=1–2 天 / L=3–5 天 / XL=>1 周。

---

## P0 — 阻碍其他重构的前置项（先做这两个）

### T1. 抽 GlassUITheme 设计 token —【M-3 / M-8】 Size: S
**Why now**：所有 UI 重构（T3 / T5）都会摸 padding/cornerRadius，先把 design token 抽出来才不会到处改完发现命名不一致。
**Approach**：
- 新建 `MeetingCountdownApp/AppShell/GlassUITheme.swift`，定义 enum `GlassUITheme { static let cornerRadiusLarge / Default / Small; paddingDefault / Compact; ... }`
- Sweep `GlassUI.swift`、`MenuBarStatusItemController.swift`、`SettingsView.swift` 全部 magic number 改成引用
- 写一条 ADR：`docs/adrs/YYYY-MM-DD-glass-ui-theme.md`
**Risk**：纯抽常量，零行为改动；几乎不会破。
**Dep**：无。

### T2. 抽 AsyncStateController 协议 + 默认实现 —【M-4 / M-2】 Size: S
**Why now**：`ReminderPreferencesController` / `SoundProfileLibraryController` / `SystemCalendarConnectionController` 三个 controller 的 refresh+isLoading+errorMessage pattern 一模一样；后面任何 controller 类的重构（T6 / T8）都会重复这套模板。
**Approach**：
- 定义 `protocol AsyncStateController { var loadingState: Bool; var errorMessage: String? ; func performRefresh() async throws }` 加 protocol extension `func refresh() async`
- 三个 controller 重命名状态字段（`isLoadingState` → `loadingState`，`isSavingState` 等并入），并依次迁移
- 同步更新对应单元测试断言
**Risk**：字段重命名属破坏性，必须全文检索调用方一次性改完
**Dep**：无（但 T1 + T2 互不冲突，可并行）

---

## P1 — 高价值重构（建议未来 2–4 周内做完）

### T3. 拆 `Presentation.swift`（1742 行）—【M-1 / M-6】 Size: M
**Why**：1742 行单文件混了 color / 日期格式 / i18n / 诊断快照，未来任何 settings UI 改动都要在里面摸黑。
**Approach**：
- `SettingsBadgePresentation.swift`（颜色/状态徽章）
- `SettingsDateFormatting.swift`（formatter 集合）
- `CalendarConnectionDiagnosticsPresenter.swift`（诊断快照构建）
- `SettingsLocalizationPresentation.swift`（暂时承载现有 `localized(_:_:)` 调用）
- 保持每个新文件 < 400 行，以原 SettingsView extension 为单元搬迁
**Risk**：纯重命名/移文件，无行为改动；要确保 xcodegen 重新生成包含新文件
**Dep**：无（可与 T1/T2 并行）
**ADR**：建议写一个 `docs/adrs/YYYY-MM-DD-presentation-split.md` 锁住边界

### T4. 拆 `MenuBarStatusItemController`（474 行 5 职责）—【M-7 / A-3】 Size: M
**Why**：现在它同时是 NSStatusItem 宿主 + popover 控制器 + ReminderState→Presentation 翻译 + 倒计时格式化 + 红闪逻辑；任何 UI 改动都要踩 5 个角色。还和 `ReminderState.menuBarAlertPresentation(at:)` 重复 presentation 计算（A-3）。
**Approach**：
1. **先决定真值方**：`ReminderMenuBarAlertPresentation` 应该完全由 `ReminderState` 产生（写一条 ADR 锁定）；`MenuBarStatusItemController` 只负责把 presentation 翻译成 NSStatusItem 外观（颜色、字体、capsule）。
2. 抽 `MenuBarPresentationCalculator`（纯函数：state → presentation；依赖时间、UI 语言）
3. 抽 `MenuBarAppKitHost`（NSStatusItem 安装 / popover 配置 / 应用 title）
4. 控制器只剩 Combine 订阅 + 把计算结果交给 host
5. 删掉 `MenuBarStatusItemController.localizedAlertPresentation`，让 `ReminderState` 单独负责
**Risk**：触及核心 UI 路径，必须有 snapshot 测试或人工 QA 校验菜单栏视觉无回退
**Dep**：T1（用 GlassUITheme）；建议 T2 先（如果引入新的 controller）

### T5. Settings 页面注册表（pluggable）—【E-4 / M-11】 Size: M
**Why**：当前 `SettingsTab` 枚举 + `SettingsView` 里 `@State` 散落 + 每个 page 是 SettingsView extension。新增 page = 改 enum + extension + state，严重违反开闭原则。
**Approach**：
- 定义 `protocol SettingsPage { var id: String; var titleKey: String; @ViewBuilder var body: some View }`
- 把 5 个 page extension 改成各自独立的 `View` struct，state 移进去（hover、expansion）
- `SettingsView` 持有一个 `[any SettingsPage]` 数组，由 `AppContainer` 注入
- 暂不引入"插件加载"，但拓扑允许未来加
**Risk**：state 移动需要小心，特别是跨页持久化的 hover / expanded
**Dep**：T1, T3（让 Presentation.swift 已经拆好再动 settings layer）

### T6. AppRuntime 拆为两个 holder —【A-1 / M-9】 Size: M
**Why**：AppRuntime 10 属性混了核心 state machine（SourceCoordinator / ReminderEngine / Preferences）和 AppKit 控制器（SettingsWindow / MenuBarStatusItem / LaunchAtLogin），UI 层伸手到 god object 拿东西。
**Approach**：
- 拆 `CoreRuntime`（state machines）和 `ShellRuntime`（AppKit 控制器、launch-at-login、status item）
- `FeishuMeetingCountdownApp` 同时持有这两个；views 只接收自己实际用的
- 移除 closure-based callback chain（A-2），改用 `Combine.PassthroughSubject<RefreshTrigger, Never>` 让所有 controller 订阅同一个 bus
**Risk**：H — 触及所有 controller 构造点，回归面广
**Dep**：T2（AsyncStateController 先到位再迁移 controller 集合）

---

## P2 — 大型方向性重构（需要先写 ADR 讨论再启动）

### T7. i18n 迁移到 `.xcstrings` —【E-3 / M-5】 Size: L
**Why**：当前所有 UI 字符串是 `localized(中, 英)` 元组散在 20+ 文件，加日语 = 全文 sweep；翻译外包没法做。
**Approach**：
- 决策点：迁到 Apple String Catalog (`.xcstrings`) vs JSON loader（写在 ADR 里）
- 写脚本扫一遍 `localized(_:_:)` 调用，自动产出 key + 中英文初始化文件
- 保留 `localized(_:_:)` 包装但改成 key-based: `func localized(_ key: String) -> String`
- 分两步落地：先拉 key + zh/en，再 sweep call site
**Risk**：M — 字符串错位会让 UI 显示 key
**Dep**：T3（先把 `Presentation.swift` 拆完，免得 1742 行边迁边乱）
**ADR**：必须

### T8. 多 source 架构 —【E-1 / A-7】 Size: L–XL
**Why**：当前 `SourceCoordinator` 持有 `private let source: any MeetingSource`（单数），加任何新 source（Google / Outlook）都要从基础类型动刀。
**Approach**：
- ADR 决定 merge 策略（按时间排序合并？per-source 状态机？）
- `SourceCoordinator` 改持 `[any MeetingSource]`；`refresh()` 并行 await 所有 source，merge → 排序
- `SourceHealthState` 升级为 per-source aggregation
- `MeetingRecord.metadata` dict 改成 typed `enum MetadataKey`（A-7）
**Risk**：H — 状态机重写，影响 reminder 调度
**Dep**：T6（runtime 拆分先完成）
**ADR**：必须，且应先做 1 个最小 PoC 接入第二个 source（Google Calendar mock）才正式 merge

### T9. 多 trigger 架构 —【E-6】 Size: L
**Why**：当前 reminder 只能"会议开始前 X 分钟"。用户经常要求"提前 30 分钟 + 5 分钟双触发"或"按响应状态触发"，目前 `ReminderEngine.reconcile()` 完全耦合单触发模型。
**Approach**：
- 定义 `protocol ReminderTrigger { var id; func nextFireDate(from:) -> Date?; func execute(for:) async throws }`
- `ReminderEngine` 持 `[any ReminderTrigger]`，每个独立 reconcile
- 新增 `BeforeStartTrigger`（封装现有逻辑，零行为变化）
- 新增 `MultipleLeadTimesTrigger` 作为第一个新 trigger 类型
**Risk**：H — 触及核心调度
**Dep**：T8 或独立做（不冲突）
**ADR**：必须

---

## P3 — 测试与诊断债

### T10. 加 UI / snapshot 测试 —【T-3 / T-9】 Size: M
**Why**：菜单栏 presentation 完全没自动化覆盖；T4 拆 controller 时需要 snapshot 兜底回归。
**Approach**：
- 选 framework：`XCUITest`（重）vs `swift-snapshot-testing`（轻、推荐）
- 先给 `MenuBarPresentationCalculator`（T4 产出）写 4–6 条 snapshot：idle / scheduled / playing(remaining > 0) / playing(overdue) / failed / disabled
- 再补 SettingsView 关键页 snapshot（基线 + dark mode）
**Dep**：T4（先拆出 calculator）

### T11. 提取共享测试 fixtures —【T-6】 Size: S
**Why**：`FixedDateProvider`、`SpyReminderAudioEngine` 等 stub 在多个测试文件复制。
**Approach**：新建 `MeetingCountdownAppTests/TestSupport/` 目录，把 5–6 个共享 stub 集中。
**Dep**：无

### T12. SwiftLint + pre-commit hook —【T-8】 Size: S
**Approach**：加 `.swiftlint.yml`（含 force-unwrap / line-length / 闭包风格）+ git pre-commit hook 调 swiftlint --fix
**Dep**：无

---

## P4 — Polish（哪天闲了再做）

| ID | Audit | 一句话 |
|---|---|---|
| T13 | A-2 | 把三处 `[weak sourceCoordinator]` callback closure 换成 PassthroughSubject 事件总线 |
| T14 | A-4 | 给 `PreferencesStore` 协议加 `@MainActor` 限定或写明 threading contract |
| T15 | A-5 | `MenuBarPresentationClock` 移进 ReminderState 自己拥有刷新节奏 |
| T16 | A-8 | `EKEventStore` 的 `nonisolated(unsafe)` 加注释 + 写一条架构断言测试 |
| T17 | R-1 | `EventKitSystemCalendarAccess.requestReadAccess()` 把系统错误包成 `MeetingSourceError.failedToRequestAccess` |
| T18 | R-6 | `ReminderEngine` 加 `.transientFailure(retryAt:)` 状态，让 audio file missing 类错误自动重试 |
| T19 | R-8 | `SoundProfileAssetStore.deleteImportedSoundProfile` 返回 `enum DeletionResult { .deleted, .alreadyMissing, .staleMetadata }` |
| T20 | R-10 | `SourceCoordinator.refresh()` 加 `Task.isCancelled` 检查避免 transient UI 不一致 |
| T21 | R-12 | `ReminderEngine` deinit 加 assertion no outstanding tasks |

---

## 暂不在 roadmap 的项（明确跳过）

签名 / 分发链路相关（S-2 / S-3 / S-4 / S-5 / S-9 / T-1 release-block 部分）：当前未加入 Apple Developer Program，暂时不动。等加入会员后另开 task list。

---

## 建议执行顺序（拓扑）

```
P0:   T1 ─┐         T2 ─┐
          │              │
P1:   T3 ─┼──> T4        ├──> T6 ──┐
          └──> T5 <──────┘         │
                                   │
P2:   T7 (after T3)                │
      T8 (after T6) ──────────────┘
      T9 (independent of T8 if you want)

P3:   T10 (after T4),  T11/T12 (independent)
P4:   随时
```

---

## Already Shipped（2026-04-22 batch 修复）

| Commit | 修复 finding |
|---|---|
| `bc7a3b0` AppLogger 默认 .private + 新增显式 public 重载 | S-1 |
| `91b4883` Refresh / 日历持久化失败不再静默吞错 | R-4, R-7 |
| `026c2b0` 音频引擎监听配置变化 + 暴露 warmup 降级 | R-2, R-3 |
| `9c0cd62` 新增 StartupError 类型与初始化错误策略文档 | R-9 |
| `4b03b41` Preferences 加 schema 版本号 + 暴露解码失败 | R-5, R-11, E-5, T-5 |
| `ef00ebd` CI 加单元测试 workflow（不依赖签名） | T-1（非签名部分） |
| `9de8a61` AGENTS.md 强化 AI 执行约束与 secrets 列表 | AI-2, AI-3, AI-4, AI-5, AI-8, AI-9 |
| 直接删除 `MeetingCountdown 2.xcodeproj/`（原本 untracked） | A-6, T-2, AI-1 |

build + 58/58 测试通过。
