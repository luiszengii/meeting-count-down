# Feishu Meeting Countdown — UI Review

**Audited:** 2026-04-03  
**Baseline:** Abstract 6-pillar standards for a native macOS utility app  
**Method:** Code-and-doc audit plus runtime screenshot review. Conclusions below are tagged as:
- `Code-backed`: directly supported by implementation or documentation structure
- `Screenshot-backed`: directly visible in the provided runtime screenshots
- `Inferred render`: likely rendered outcome based on SwiftUI/AppKit layout and native control behavior

**Screenshots reviewed**
- Menu bar popover
- Menu bar status item while active
- Settings window

---

## Overall Score

**14/24**

The app already behaves like a real macOS utility rather than a generic dashboard, and the product model is focused. The downgrade from the previous code-only review comes from what the screenshots confirm: the UI is more cramped, flatter, and more tool-like than the code alone suggested. The main issue is not missing states. It is that hierarchy, polish, and action focus are still underdeveloped across all primary surfaces.

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 3/4 | Specific and operational, but often too dense and repeated across surfaces. |
| 2. Visuals | 2/4 | Functionally native, but visually flat and closer to an internal utility than a polished menubar product. |
| 3. Color | 2/4 | Semantic colors are correct, but screenshot evidence shows over-muted dark surfaces and weak emphasis hierarchy. |
| 4. Typography | 2/4 | Native typography choices are correct in principle, but too much important information is small, dim, and compressed in practice. |
| 5. Spacing | 2/4 | Spacing tokens are consistent in code, yet the rendered result is crowded and does not create enough macro hierarchy. |
| 6. Experience Design | 3/4 | State coverage is strong, but primary actions and setup progression are still weaker than the status explanation. |

---

## Top Fixes

1. **Redesign the settings window around task priority, not implementation completeness**  
   The screenshot confirms that the current settings UI reads like a vertically stacked control dump. Split it into `接入与权限`, `提醒`, `同步与诊断`, `高级`, and add a top summary strip with `连接状态 / 已选日历 / 下一场会议 / 提醒是否生效`.

2. **Promote the popover from “status readout” to “command surface”**  
   The screenshot shows a large, dark popover where the most visually dominant elements are three generic buttons. Add one state-aware primary action and remove duplicated text so the panel feels intentional rather than transitional.

3. **Refine visual density and emphasis for macOS native fit**  
   The current UI is technically native but visually heavy-dark, low-contrast, and caption-biased. Increase type hierarchy, reduce redundant helper text, and use stronger section rhythm instead of relying on repeated `GroupBox` containers and dark rounded cards.

---

## Surface Review

### 1. Installation Page / Manual Installation Document UX

**Score signal:** accurate and honest, but still maintainer-first rather than tester-first.

**What works**
- `Code-backed`: The documentation is explicit about the only supported architecture and avoids vague “supports calendar sync” language.
- `Code-backed`: The install guide correctly distinguishes launch trust friction from Calendar permission reliability on another Mac, which prevents a real support trap.
- `Code-backed`: The document gives concrete paths and OS labels, which is critical for a non-App-Store utility.

**Issues**
- `Code-backed`: The document still starts by classifying package types and tester categories before presenting the shortest successful install path.
- `Code-backed`: The user must mentally stitch together three systems: Feishu, macOS Calendar, and this app. There is still no compact “success path” or visual checkpoint block.
- `Inferred render`: Because the first screenful is caveat-heavy, the document projects “advanced unsigned test artifact” before it projects “small helpful menu bar app.”

**Recommended changes**
- Add `最快安装路径` as the first section with only the five actions most testers need.
- Add `完成后你应该看到什么` immediately after installation.
- Move maintainer export commands and signed/unsigned distinctions lower in the document.
- Add one compact architecture line near the top of README and manual installation:
  `飞书 CalDAV -> macOS 日历 -> Feishu Meeting Countdown`.

### 2. Menu Bar Status Chip / Status Item Appearance

**Score signal:** solid implementation, but the active-state screenshot exposes weak visual identity and awkward selection behavior.

**What works**
- `Code-backed`: Moving to `NSStatusItem` was the correct technical decision for countdown styling and width control.
- `Code-backed`: The item uses truncation, monospaced digits, and capped width correctly for a time-based menu bar utility.
- `Screenshot-backed`: The icon + label format is immediately legible, and the “就绪” state is understandable at a glance.

**Issues**
- `Screenshot-backed`: The active-state screenshot shows a bright blue system highlight block with the app icon and `就绪`. This is functional, but it reads more like a selected menu item than a crafted utility presence. There is little brand or state nuance once the item is active.
- `Screenshot-backed`: The current quiet state feels too generic. It does not yet convey “meeting-aware utility” strongly enough when compared with the stronger countdown/red-alert concept described in code.
- `Inferred render`: The transition between passive, upcoming, and urgent states is likely too subtle outside the final alert window.

**Recommended changes**
- Define three visually distinct states:
  `idle`, `meeting soon`, `urgent countdown`.
- In quiet state, consider a lighter custom capsule or softer status treatment instead of relying only on default active-blue selection behavior.
- Simplify the leading icon in urgent states so the timing information becomes the hero.

### 3. Clicked Dropdown Card / Popover Content

**Score signal:** the screenshot confirms this is the weakest primary surface right now.

**What works**
- `Code-backed`: The popover is structurally clean and avoids overcomplicated nesting.
- `Screenshot-backed`: The dark card shape, rounded corners, and segmented layout feel plausible for a modern macOS utility shell.
- `Code-backed`: The action list is minimal and understandable.

**Issues**
- `Screenshot-backed`: The first two lines are effectively repeating the same message:
  `已连接 1 个系统日历，当前暂无可提醒会议`
  appears both as bold headline and as secondary text. This wastes the most valuable visual space in the panel.
- `Screenshot-backed`: The buttons are visually oversized and too equal in weight. `立即刷新`, `打开设置`, and `退出` all read like primary controls, which flattens intent.
- `Screenshot-backed`: The panel has a lot of dark empty area relative to the amount of useful information. It feels like a large shell with too little curated content inside.
- `Code-backed`: There is still no direct meeting-oriented or setup-oriented primary action. When the app has no meeting, the popover should help the user recover, not just restate the state.
- `Screenshot-backed`: The focus ring on `立即刷新` is visually louder than the information hierarchy above it.

**Recommended changes**
- Remove the duplicated secondary line; use that space for one actionable next step.
- Add a dynamic primary action:
  `打开“日历”检查同步`,
  `去授权日历`,
  `查看下一场会议`,
  depending on current state.
- Turn secondary actions into lower-contrast rows or a footer action group.
- Reduce vertical bulk so the panel feels compact and purpose-built.

### 4. Settings Page

**Score signal:** comprehensive but overcrowded; the screenshot confirms the current hierarchy problem is stronger than the code alone suggested.

**What works**
- `Code-backed`: The page covers the correct product responsibilities for a menu bar utility.
- `Code-backed`: Permission branches and system state handling are complete and mature.
- `Code-backed`: The control vocabulary is native and appropriate for macOS.

**Issues**
- `Screenshot-backed`: The settings window is visually dense to the point of fatigue. Nearly every section uses the same dark panel treatment, the same narrow width, and similarly weighted text blocks, so nothing clearly becomes the first thing to do.
- `Screenshot-backed`: Important headings and explanations are too small relative to the amount of content. The page reads like a debug/admin preferences pane rather than a polished single-purpose consumer utility.
- `Screenshot-backed`: The calendar list is visually noisy. Individual calendar rows look like standalone dark tags piled inside another dark group, which compounds surface heaviness.
- `Screenshot-backed`: The audio section becomes especially crowded once multiple profiles exist. `播放 / 使用 / 删除` appear as a repeated action cluster on every row, which creates operational noise.
- `Code-backed`: `当前应用状态` sits too low to serve as the global summary, yet still duplicates state already implied above.

**Recommended changes**
- Replace the current single scroll narrative with a clearer macro layout:
  top summary card,
  then setup,
  then reminder behavior,
  then sync/system integration,
  then advanced/runtime detail.
- Merge `唯一接入路径` and `CalDAV / 系统日历配置` into one stronger onboarding/configuration block.
- Reduce helper prose by converting critical guidance into inline labels, checklists, and summary chips.
- Redesign sound rows into:
  title + status badge on the left,
  `试听` as secondary action,
  trailing menu for `使用 / 删除`.
- Increase contrast between heading tiers and body tiers; too much of the page currently falls into “small gray text”.

---

## Detailed Findings By Pillar

### Pillar 1: Copywriting (3/4)

- `Code-backed`: The copy is specific and operational. It avoids generic placeholders and generally tells the user what to do.
- `Screenshot-backed`: The popover reveals a repetition problem. The same state is expressed twice with almost no informational gain.
- `Code-backed`: The settings page still leans on explanatory prose instead of compressing system behavior into clearer UI structure.

### Pillar 2: Visuals (2/4)

- `Screenshot-backed`: The popover and settings window are both flatter and heavier than the code implied. The surfaces feel more utilitarian than designed.
- `Screenshot-backed`: The settings window especially lacks a focal anchor. It is a stack of dark blocks rather than a guided control panel.
- `Code-backed`: The app is using appropriate native controls, so the problem is not wrong platform vocabulary; it is weak composition and emphasis.

### Pillar 3: Color (2/4)

- `Code-backed`: Semantic color logic is sound.
- `Screenshot-backed`: In practice, the dark surfaces are too similar in value. Cards, row backgrounds, and outer canvas compress into one heavy layer.
- `Screenshot-backed`: The bright blue active/focus treatments draw more attention than the underlying information architecture, especially in the popover.

### Pillar 4: Typography (2/4)

- `Code-backed`: Native typography choices are fundamentally correct.
- `Screenshot-backed`: The rendered settings window shows too much critical content in small, dim styles. The information density outpaces the type hierarchy.
- `Screenshot-backed`: The popover headline is strong enough, but the repeated secondary line and oversized button labels create imbalance.

### Pillar 5: Spacing (2/4)

- `Code-backed`: Spacing tokens are internally consistent.
- `Screenshot-backed`: The popover wastes space at the macro level while still feeling cramped at the content level.
- `Screenshot-backed`: The settings page packs too many similar blocks into a narrow frame, making it scan vertically like a log rather than a preference surface.

### Pillar 6: Experience Design (3/4)

- `Code-backed`: The app has good state coverage and does not hide system realities from the user.
- `Screenshot-backed`: The surfaces explain status better than they guide next action.
- `Code-backed`: The menu bar utility model would be much stronger if the popover and settings top section each answered one question first:
  `What is happening now?`
  `What should I do next?`

---

## Priority Surface-Specific Fixes

### Popover

1. Remove duplicate state line.
2. Add one dynamic primary action.
3. Demote `退出` and `打开设置` to footer/secondary treatment.
4. Reduce overall vertical padding and make the panel feel tighter.

### Menu Bar Status Item

1. Add stronger distinction between passive and upcoming states.
2. Review active/selected appearance against actual macOS menu bar behavior, not just custom drawing logic.
3. Make timing/status meaning more memorable than generic utility presence.

### Settings Window

1. Add a summary header strip at top.
2. Merge setup explanation with configuration UI.
3. Break sections into clearer hierarchy and reduce helper text volume.
4. Simplify sound profile row actions.

### Installation UX

1. Put tester quickstart first.
2. Add success checkpoint states.
3. Move maintainer/export/signing detail to lower sections.

---

## Files Audited

- `AGENTS.md`
- `README.md`
- `docs/manual-installation.md`
- `MeetingCountdownApp/AppShell/AGENTS.md`
- `MeetingCountdownApp/AppShell/MenuBarStatusItemController.swift`
- `MeetingCountdownApp/AppShell/MenuBarContentView.swift`
- `MeetingCountdownApp/AppShell/SettingsView.swift`
- `MeetingCountdownApp/AppShell/FeishuMeetingCountdownApp.swift`

**Runtime screenshots incorporated**
- Menu bar popover screenshot
- Menu bar status item screenshot
- Settings window screenshot
