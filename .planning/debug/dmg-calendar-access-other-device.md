---
status: investigating
trigger: "Investigate issue: dmg-calendar-access-other-device"
created: 2026-04-03T00:00:00+08:00
updated: 2026-04-06T10:00:00+08:00
---

## Current Focus

hypothesis: 现有 UI 虽然能区分“未授权”和“无可读日历”，但仍无法把“签名身份不稳定导致跨设备权限失效”与“CalDAV 尚未同步”拆开，所以用户仍会把 unsigned 包问题误读成日历配置问题。
test: 在运行时增加一个独立的代码签名稳定性诊断项，并把它接到设置页里，与现有系统日历权限/同步新鲜度并列展示。
expecting: 如果这个假设成立，修复后用户在另一台机器上能直接看到“当前构建缺少稳定签名身份，不适合验证跨设备 Calendar 权限”，从而不再把问题误归因到 CalDAV 或授权按钮。
next_action: 设计并实现代码签名诊断检查器，接入 Diagnostics 和 Settings UI，然后做本地验证。

## Symptoms

expected: After installing the app from the DMG on another macOS device, granting Calendar access in System Settings should allow the app to read EventKit calendars and load synced Feishu meetings.
actual: On another device, the user's app still cannot access Calendar data even after Calendar access appears to be enabled in System Settings.
errors: User reports the app cannot access Calendar. Existing pitfall doc mentions typical app-side state like “尚未决定是否允许访问日历”, but no fresh exact error string from the affected machine is available yet.
reproduction: 1. Build/export DMG from this repo. 2. Pass DMG to another macOS device. 3. Install/open app. 4. User enables Calendar access/full access in System Settings. 5. App still cannot read calendars.
started: Issue observed during Phase 6 manual distribution testing on 2026-04-03. Local development machine had working Calendar integration earlier; issue appears specifically in distributed DMG on another device.

## Eliminated

- hypothesis: app 在用户去系统设置改权限后没有刷新 EventKit 授权状态，导致 UI 误判为仍不可读。
  evidence: `SystemCalendarConnectionController.refreshState()` 每次都会重新读取 `calendarAccess.currentAuthorizationState()`，且设置页和 `EKEventStoreChanged` 通知都会触发刷新。
  timestamp: 2026-04-03T11:18:00+08:00

## Evidence

- timestamp: 2026-04-03T00:05:00+08:00
  checked: .planning/debug/knowledge-base.md
  found: 仓库里当前不存在知识库文件，没有可复用的已解决模式。
  implication: 需要从零建立这次调试结论，不能直接套用历史 root cause。

- timestamp: 2026-04-03T00:06:00+08:00
  checked: MeetingCountdownApp/SystemCalendarBridge/SystemCalendarAccess.swift
  found: 权限实现调用 `EKEventStore.requestFullAccessToEvents()`，授权状态映射也覆盖了 `fullAccess`、`notDetermined`、`denied`、`restricted`、`writeOnly`。
  implication: app 端 EventKit API 选型和状态映射没有暴露出新的明显缺陷，问题更像是系统没有把授权正确绑定到分发产物身份。

- timestamp: 2026-04-03T00:07:00+08:00
  checked: scripts/export-release.sh, scripts/create-dmg.sh, project.yml
  found: 导出脚本和工程配置都显式设置 `CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO`，DMG 只是包装现有 `.app`，没有补任何额外签名。
  implication: 当前 Phase 6 产物是刻意按“未正式签名”路径分发，不具备稳定代码身份。

- timestamp: 2026-04-03T00:08:00+08:00
  checked: build/manual-release/FeishuMeetingCountdown.app/Contents/Info.plist
  found: `CFBundleIdentifier` 是 `com.luiszeng.meetingcountdown`，且存在 `NSCalendarsFullAccessUsageDescription`。
  implication: 这次问题不是缺 usage description，也不是 Info.plist bundle id 缺失。

- timestamp: 2026-04-03T00:09:00+08:00
  checked: codesign -dv --verbose=4, codesign -d -r-, spctl -a -t exec -vv on build/manual-release/FeishuMeetingCountdown.app
  found: `codesign -dv` 显示 `Signature=adhoc`、`Identifier=FeishuMeetingCountdown`、`Info.plist=not bound`；`codesign -d -r-` 直接报 `code object is not signed at all`；`spctl` 报 `source=no usable signature`。
  implication: macOS 实际把该分发 app 视为没有可用签名身份，当前分发形态不足以作为稳定的权限授权载体。

- timestamp: 2026-04-03T11:18:00+08:00
  checked: MeetingCountdownApp/SystemCalendarBridge/SystemCalendarConnectionController.swift and SystemCalendarMeetingSource.swift
  found: 权限状态会在设置页刷新、授权动作完成后、以及 `EKEventStoreChanged` 通知后重新读取；读取日历前也会再次检查 `currentAuthorizationState()`。
  implication: “系统设置改完权限但 app 没刷新状态”不是主因，根因仍落在分发身份。

- timestamp: 2026-04-03T11:19:00+08:00
  checked: scripts/export-release.sh, scripts/create-dmg.sh, docs/manual-installation.md, docs/pitfalls/unsigned-dmg-calendar-permission-on-other-mac.md
  found: 已新增 `--signing-identity` 支持，导出包命名会区分 `signed|unsigned`；文档也明确把 unsigned 包降级为“只验证 Gatekeeper/安装流程”，要求跨设备 Calendar 权限测试必须先签名。
  implication: 仓库层面的修复已经落地，剩余验证依赖真实第二台机器和可用签名身份。

- timestamp: 2026-04-03T11:19:30+08:00
  checked: security find-identity -v -p codesigning
  found: 当前开发机输出 `0 valid identities found`。
  implication: 本机会话无法自证签名分发链路，只能完成脚本语法与帮助入口验证，最终效果必须走人工跨机验证。

- timestamp: 2026-04-06T10:00:00+08:00
  checked: human-verify checkpoint response
  found: 用户在另一台 macOS 设备上仍报告“打开 Calendar 权限后也无法读取日历”，但当前未知所测 DMG 是默认 unsigned 包还是使用 `--signing-identity` 重建后的 signed 包。
  implication: 现阶段还不能把“修复无效”当成事实，必须先区分是错误测试对象，还是存在签名之外的第二根因。

- timestamp: 2026-04-06T10:08:00+08:00
  checked: project.yml, SystemCalendarConnectionController.swift, SystemCalendarMeetingSource.swift, build/manual-release/FeishuMeetingCountdown.app codesign status
  found: 工程仍未声明额外 calendar entitlement；运行时权限链路仍只依赖 `NSCalendarsFullAccessUsageDescription` + EventKit 状态检查；当前工作区产物仍是 `Signature=adhoc` / `source=no usable signature`。
  implication: 仓库里暂时没有发现“已签名包仍必然失败”的第二个明显技术缺口，现阶段更像是测试对象身份不明确，而不是业务权限代码又坏了。

- timestamp: 2026-04-06T10:12:00+08:00
  checked: SettingsView.swift connection section
  found: 当权限已授权但 `availableCalendars` 为空时，设置页只会提示“请先确认飞书 CalDAV 已经成功同步到 macOS 日历”，没有任何签名稳定性提示。
  implication: 如果实际问题是 unsigned 分发包，当前 UI 会把“签名身份问题”伪装成“系统日历没有同步”，用户很难自助定位。
## Resolution

root_cause: 当前 Phase 6 导出的 DMG / zip / app 默认没有稳定代码签名身份；对另一台 macOS 机器上的 Calendar / EventKit 权限来说，这种 unsigned 分发包不是可靠的 TCC 授权主体，所以系统设置里看似已打开权限，运行中的 app 仍可能无法读取日历。
fix: 给 `scripts/export-release.sh` 和 `scripts/create-dmg.sh` 增加可选 `--signing-identity` 参数，在不接入 Developer ID / notarization 的前提下也能导出带稳定代码签名身份的测试包；同时更新安装说明、README、docs 索引和 pitfall，明确 unsigned 包只适合验证安装/放行流程，不适合跨设备 Calendar 权限验证。
verification: 已完成脚本语法检查 `bash -n`，并验证两个脚本的 `--help` 输出已包含新参数和适用边界说明。由于当前机器没有任何可用代码签名身份，尚未能在本地生成 signed 包并在第二台 macOS 上完成端到端 Calendar 权限回归。
files_changed: ["scripts/export-release.sh", "scripts/create-dmg.sh", "docs/manual-installation.md", "docs/pitfalls/unsigned-dmg-calendar-permission-on-other-mac.md", "docs/pitfalls/README.md", "docs/README.md", "README.md", "docs/dev-logs/2026-04-03.md"]
