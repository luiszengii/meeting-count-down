# 2026-04-22 将 1742 行 Presentation.swift 拆分为四个主题文件

- 状态：Accepted
- 日期：2026-04-22
- 关联日志：暂无

## 背景

审计问题 M-1（单文件过长）和 M-6（展示态语义混杂）指出，`MeetingCountdownApp/AppShell/Settings/Presentation.swift` 已增长至 1742 行，囊括了四个语义截然不同的职责：

1. 徽章颜色与徽章文案推导（color mapping、badge text 计算）
2. 日期 / 时长格式化（`DateFormatter`、时长本地化、相对时间描述）
3. 日历连接诊断快照构建（`CalendarConnectionDiagnosticSnapshot` 及导出辅助）
4. i18n 桥接（`localized(_:_:)` 函数、语言偏好读取和 `Binding` 封装）

这四种职责的修改频率和测试边界都不同，堆在单一文件里使得阅读、审查和后续迁移的认知成本持续升高。本决策对应重构路线图（refactor-roadmap-2026-04-22.md）任务 T3。

## 决策

在不改变任何函数签名、行为或访问控制的前提下，把 `Presentation.swift` 中的成员按语义切分到以下四个新文件，同时保留原文件作为残余容器，存放不属于任何单一主题的跨切面辅助成员及文件级类型定义：

| 目标文件 | 迁入内容 | 约行数 |
|---|---|---|
| `SettingsBadgePresentation.swift` | `authorizationBadgeColor`、`diagnosticBadgeColor`、`openCalendarPrivacySettings`、所有 `*BadgeColor`、`*BadgeText`、`*Badges`、`reminderStatusSymbolName` 等 | ~265 行 |
| `SettingsDateFormatting.swift` | `absoluteFormatter`、`englishMonthSymbols`、`localizedDateHeadline`、`localizedCountdownLine`、`localizedElapsedDescription`、`localizedDurationLine`、`localizedFutureDurationDescription`、`localizedLeadTimeDescription`、`localizedScheduledReminderLine`、`effectiveCountdownSeconds`、`effectiveCountdownDurationLine` 等 | ~215 行 |
| `CalendarConnectionDiagnosticsPresenter.swift` | `calendarConnectionDiagnosticSnapshot`、`copyCalendarConnectionDiagnosticReport`、`localizedCalendarConnectionDiagnosticSummary`、`localizedStoredCalendarSelectionSummary`、`localizedAvailableCalendarSummary`、`localizedAdvanced*` 系列 | ~130 行 |
| `SettingsLocalizationPresentation.swift` | `localized(_:_:)`、`uiLanguage`、`interfaceLanguageBinding`、`reminderCountdownModeBinding`、`manualCountdownSecondsBinding` | ~65 行 |

`Presentation.swift` 剩余约 660 行，保留跨页面通用展示态推导（状态摘要、日历过滤、overview 卡文案等）和全部文件级枚举 / 结构体 / 过渡动画扩展。文件顶部增加注释说明拆分背景和已迁出内容。

每个新文件均作为 `extension SettingsView { ... }` 块存在，保留原有 `private` / `internal` 访问控制。各文件仅引入其内容实际需要的模块（`Foundation`、`SwiftUI`、`AppKit`）。

## 备选方案

### 方案 A：维持单一 1742 行文件

没有采用。该文件已超出任何合理的单文件阈值，继续追加内容只会加剧审查成本，且与 M-1 / M-6 的修复目标直接冲突。

### 方案 B：按视觉层级（页面 Tab）而不是语义切分

没有采用。设置页的展示辅助方法会被多个 Tab 共享（如 `localizedDateHeadline` 被概览页、日历页和提醒页共用），按 Tab 切分会导致大量重复或复杂的跨文件引用，与"减少混杂"的初衷相悖。

## 影响

- 四个新文件均通过 xcodegen path glob 自动纳入构建，无需修改 `project.yml`。
- `SettingsView.swift` 无需改动（新文件均为 `extension SettingsView`）。
- 本次拆分为纯文件组织重构，零行为变更，不影响任何测试。
- `localized(_:_:)` 函数已集中到 `SettingsLocalizationPresentation.swift`，为 P2 T7 的完整 i18n 迁移提供单一替换入口。

## 后续动作

1. P2 T7（i18n 整体迁移）将以 `SettingsLocalizationPresentation.swift` 为入口替换 `localized(_:_:)` 实现，其他三个主题文件无需随之改动。
2. 如果 `Presentation.swift` 的残余部分在后续审计中进一步增长，可继续按相同原则拆出第五个主题文件。
