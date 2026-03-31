---
generated: 2026-04-01
focus: concerns
---

# Codebase Concerns

**Analysis Date:** 2026-04-01

---

## Technical Debt

**Silent error swallowing on preferences persistence:**
- Issue: All three calendar-selection save calls in `SystemCalendarConnectionController` use `try?`, silently discarding errors. If `UserDefaults` write fails (e.g., disk full, sandboxing issue), the in-memory state and persisted state silently diverge.
- Files: `MeetingCountdownApp/SystemCalendarBridge/SystemCalendarConnectionController.swift` lines 97, 100, 139
- Impact: User's calendar selection may not survive an app restart with no indication of failure.
- Fix approach: Log the error via `AppLogger` at minimum; consider surfacing a `lastErrorMessage` on persistence failure.

**`NSDataDetector` instantiation silently fails:**
- Issue: `try? NSDataDetector(...)` in the URL extractor throws away the error. If detector construction fails, links are silently omitted from all meeting records.
- Files: `MeetingCountdownApp/SystemCalendarBridge/SystemCalendarModels.swift` line 151
- Impact: Meeting links (VC join URLs) could silently disappear without any diagnostic signal.
- Fix approach: Use `try` with a caught error logged via `AppLogger`, or pre-construct a static shared detector.

**`DateComponentsFormatter` allocated on every `countdownLine` call:**
- Issue: `SourceCoordinator.countdownLine(until:)` allocates a fresh `DateComponentsFormatter` on each invocation. The menu bar reads `menuBarTitle` on every SwiftUI update tick.
- Files: `MeetingCountdownApp/SourceCoordinator/SourceCoordinator.swift` lines 192–196
- Impact: Unnecessary allocations each render pass; formatter allocation is moderately expensive.
- Fix approach: Promote to a `static let` pair (one for `>= 3600`, one for `< 3600`), or lazily cache by unit set.

**Duplicate `DateFormatter` instances across modules:**
- Issue: Three separate `static let absoluteFormatter`/`timeFormatter` date formatters with identical configuration exist in `SourceCoordinator`, `SettingsView`, and `ReminderState`. Shared formatting logic is not centralised.
- Files:
  - `MeetingCountdownApp/SourceCoordinator/SourceCoordinator.swift` lines 210–214
  - `MeetingCountdownApp/AppShell/SettingsView.swift` lines 281–285
  - `MeetingCountdownApp/ReminderEngine/ReminderState.swift` lines 117–121
- Impact: Low risk today, but any locale/style change must be made in three places.
- Fix approach: Centralise in a `AppFormatters` namespace in `Shared/`.

**`StubMeetingSource` and `InMemoryPreferencesStore` shipped in production target:**
- Issue: Both are defined in `MeetingCountdownApp/` (not the test target), meaning they are compiled into the production binary.
- Files:
  - `MeetingCountdownApp/SourceCoordinator/StubMeetingSource.swift`
  - `MeetingCountdownApp/Preferences/PreferencesStore.swift` (lines 21–65, `InMemoryPreferencesStore`)
- Impact: Dead code in the production binary; minor binary size cost; risk of accidentally using stubs in production if wiring is changed.
- Fix approach: Move to test target or conditionally compile with `#if DEBUG`.

**`DiagnosticsState` / `DiagnosticsProviding` / `DefaultDiagnosticsProvider` unused in production UI:**
- Issue: The entire Diagnostics module (`DiagnosticsState.swift`, `DiagnosticCheckers.swift`) is compiled and instantiated nowhere in `AppContainer`. `DefaultDiagnosticsProvider` and `StubDiagnosticsProvider` exist but are never called.
- Files:
  - `MeetingCountdownApp/Diagnostics/DiagnosticsState.swift`
  - `MeetingCountdownApp/Diagnostics/DiagnosticCheckers.swift`
- Impact: Dead code increases maintenance surface; test coverage for this module is minimal (only one mapping test).
- Fix approach: Either wire the diagnostics snapshot into a visible health-check flow in the settings UI, or remove the module until it is needed.

**`RefreshTrigger` cases without listeners:**
- Issue: `wakeFromSleep`, `networkRestored`, `timezoneChanged`, and `sourceChanged` are defined in `RefreshTrigger` but no system observer registers for these events anywhere in the codebase.
- Files: `MeetingCountdownApp/Domain/RefreshTrigger.swift` lines 12–18
- Impact: Calendar data will go stale after sleep, network change, or timezone shift. The user must manually refresh or wait for the `EKEventStoreChanged` notification to fire. This is a real reliability gap for a reminder app.
- Fix approach: Register `NSWorkspaceDidWakeNotification` for `wakeFromSleep`; `NWPathMonitor` for `networkRestored`; `NSSystemTimeZoneDidChangeNotification` for `timezoneChanged`.

**`ReminderEngine.stopAll()` never called:**
- Issue: `stopAll()` provides graceful shutdown of audio and subscriptions, but there is no app lifecycle hook (e.g., `applicationWillTerminate`) calling it.
- Files: `MeetingCountdownApp/ReminderEngine/ReminderEngine.swift` line 134
- Impact: In-flight `Task.sleep` tasks will be cancelled by the OS at termination, but AVAudioEngine may not be cleanly stopped; not a crash risk but may generate OS warnings.
- Fix approach: Add a `scenePhase.inactive` / `.background` or `applicationWillTerminate` observer in `AppRuntime` or `FeishuMeetingCountdownApp`.

**`ReminderAudioEngine.warmUp()` never called proactively:**
- Issue: `warmUp()` is defined as a pre-heat API but is only invoked lazily inside `defaultSoundDuration()` and `playDefaultSound()`. There is no early call at app startup.
- Files: `MeetingCountdownApp/ReminderEngine/ReminderAudioEngine.swift` line 9; `MeetingCountdownApp/AppShell/AppContainer.swift`
- Impact: First reminder playback incurs the full AVAudioEngine startup latency (can be 50–200 ms), potentially clipping the first tone.
- Fix approach: Call `audioEngine.warmUp()` from `AppContainer.makeAppRuntime()` inside a detached `Task`.

---

## Security Considerations

**No App Sandbox configured:**
- Risk: `project.yml` disables code signing (`CODE_SIGNING_ALLOWED: NO`, `CODE_SIGNING_REQUIRED: NO`) and there is no `.entitlements` file, meaning the app runs without App Sandbox. This blocks Mac App Store distribution and means there are no entitlement restrictions on filesystem access.
- Files: `project.yml` lines 10–11
- Current mitigation: App only reads EventKit data and writes to `UserDefaults`; attack surface is minimal.
- Recommendations: Add an entitlements file with `com.apple.security.app-sandbox = YES` and `com.apple.security.personal-information.calendars = YES` before any distribution attempt. This is required for notarization as well.

**`NSApplication.activate(ignoringOtherApps: true)` is deprecated in macOS 14+:**
- Risk: Both `MenuBarContentView` (line 101) and `SettingsWindowController` (line 24) call `activate(ignoringOtherApps:)` which is deprecated from macOS 14. The replacement is `NSApp.activate()`.
- Files:
  - `MeetingCountdownApp/AppShell/MenuBarContentView.swift` line 101
  - `MeetingCountdownApp/AppShell/SettingsWindowController.swift` line 24
- Current mitigation: Still functional under Swift 6 / macOS 14 deployment target; generates compile warnings.
- Recommendations: Replace with `NSApp.activate()` unconditionally since the deployment target is macOS 14.

**Hardcoded macOS privacy settings URL:**
- Risk: The URL `"x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"` is a private scheme that Apple has changed between macOS versions.
- Files: `MeetingCountdownApp/AppShell/SettingsView.swift` line 273
- Current mitigation: Works on current macOS versions; the `guard let` prevents a crash if parsing fails.
- Recommendations: Use `SMAppService.openSystemSettingsLoginItems()` pattern or the `Settings.Privacy.Calendars` URL constant if Apple provides one; add a fallback path if the URL opens incorrectly.

---

## Missing Error Handling

**`EventKitSystemCalendarAccess.fetchCalendars()` and `fetchEventPayloads()` are synchronous on `@MainActor`:**
- Problem: `EKEventStore.calendars(for:)` and `EKEventStore.events(matching:)` are synchronous calls running on the main thread. For large calendars (many events in the 30-minute lookback + 24-hour lookahead window), this blocks the main thread.
- Files: `MeetingCountdownApp/SystemCalendarBridge/SystemCalendarAccess.swift` lines 51–53, 66–96
- Impact: UI freeze risk on calendars with many recurring events within the time window.
- Fix approach: Offload to a background actor or use `Task.detached` before calling into EventKit.

**Force unwraps in `GeneratedToneReminderAudioEngine`:**
- Problem: Two force unwraps exist: `AVAudioFormat(...)!` (line 45) and `AVAudioPCMBuffer(...)!` (line 102). While these specific arguments are always valid, they will crash the app if AVFoundation ever returns `nil` (e.g., hardware not available).
- Files: `MeetingCountdownApp/ReminderEngine/ReminderAudioEngine.swift` lines 45, 102
- Impact: Hard crash with no recovery path.
- Fix approach: Use `guard let` with a fallback (e.g., log error, set `hasWarmedUp = false`) or throw from the initialiser.

**`SettingsWindowAccessor.updateNSView` fires on every SwiftUI body invalidation:**
- Problem: `updateNSView` calls `resolveWindow(for:)` unconditionally, scheduling a `DispatchQueue.main.async` block on every re-render pass, which calls `activateKnownWindow()` (bringing the window to front) even when the user has not requested it.
- Files: `MeetingCountdownApp/AppShell/SettingsWindowController.swift` lines 42–54
- Impact: The settings window may jump to front unexpectedly whenever any observed state changes (e.g., a meeting refresh) while the settings view is open.
- Fix approach: Add a guard in `updateNSView` to only call `resolveWindow` if the window reference is not already resolved; separate the `register` callback from the `activateKnownWindow` call.

---

## Incomplete Features / Stubs

**`MeetingParticipantResponseStatus` and `attendeeResponse` field are never populated:**
- Problem: `MeetingRecord.attendeeResponse` is modelled and has a `declined` case, but `SystemCalendarEventNormalizer.makeMeetingRecord` always leaves it at the default `.unknown` because `EKEvent.availability` / `EKParticipant` status is not read.
- Files:
  - `MeetingCountdownApp/Domain/MeetingRecord.swift` lines 29, 46, 58
  - `MeetingCountdownApp/SystemCalendarBridge/SystemCalendarModels.swift` lines 102–120
- Impact: "Only remind me for accepted meetings" filtering cannot be built until this is populated. Currently all meetings including declined ones can trigger reminders.
- Fix approach: Read `EKEvent.attendees` for the self-participant's `EKParticipantStatus` and map it.

**`MeetingRecord.metadata` is never written or read:**
- Problem: The `metadata: [String: String]` escape-hatch field is defined but nothing writes to it and nothing reads from it. It carries allocation cost with no value.
- Files: `MeetingCountdownApp/Domain/MeetingRecord.swift` lines 32, 47, 59
- Impact: Negligible today; risks becoming a permanent unused field.
- Fix approach: Remove until actually needed, or document a concrete planned use.

**`ReminderPreferences` controls are not exposed in the settings UI:**
- Problem: `SettingsView` shows reminder *status* but provides no controls for `globalReminderEnabled`, `isMuted`, or `countdownOverrideSeconds`. The user cannot change reminder preferences from the UI.
- Files: `MeetingCountdownApp/AppShell/SettingsView.swift` (no reminder prefs controls); `MeetingCountdownApp/Preferences/ReminderPreferences.swift`
- Impact: Core app features (mute, disable reminders, custom lead time) are inaccessible to users.
- Fix approach: Add a "Reminder Settings" section to `SettingsView` with a toggle for enable/mute and a numeric field for countdown seconds.

**Empty `OnboardingRouter` directories remain in both app and test targets:**
- Problem: `MeetingCountdownApp/OnboardingRouter/` and `MeetingCountdownAppTests/OnboardingRouter/` are empty directories left over from the multi-source architecture cleanup.
- Files: `MeetingCountdownApp/OnboardingRouter/` (empty), `MeetingCountdownAppTests/OnboardingRouter/` (empty)
- Impact: Confusing for contributors; may cause Xcode group warnings; implies orphaned module structure.
- Fix approach: Remove both directories and re-run `xcodegen generate`.

**`DiagnosticsSnapshot` not surfaced to user:**
- Problem: `DiagnosticsSnapshot` with `items` for structured health display is fully built but never shown in any UI. The app only shows inline status text in `SettingsView`.
- Files: `MeetingCountdownApp/Diagnostics/DiagnosticsState.swift` lines 92–112
- Impact: The designed health-check UX is absent; users have no structured way to diagnose problems.

---

## Test Coverage Gaps

**`DiagnosticCheckersTests` has only one test case:**
- What's not tested: `writeOnly`, `notDetermined`, `restricted`, `denied`, and `unknown` mapping paths in `SystemCalendarPermissionDiagnostic`.
- Files: `MeetingCountdownAppTests/Diagnostics/DiagnosticCheckersTests.swift`
- Risk: Regression in these mapping paths goes undetected.
- Priority: Low (display-only, low-risk mappings).

**No tests for `SourceCoordinator.menuBarTitle` / `countdownLine` rendering:**
- What's not tested: The countdown string formatting logic — sub-60s shows "即将开始", 60s–3600s shows minutes, above shows hours + minutes. The `countdownLine` method is private but the observable surface is `menuBarTitle`.
- Files: `MeetingCountdownApp/SourceCoordinator/SourceCoordinator.swift` lines 86–102, 185–198
- Risk: Formatting regressions in the menu bar's primary display.
- Priority: Medium.

**No tests for `ReminderState` display strings:**
- What's not tested: `summary` and `detailLine` computed strings for each enum case, including the `triggeredImmediately` branch differences.
- Files: `MeetingCountdownApp/ReminderEngine/ReminderState.swift`
- Risk: Text regressions in user-facing status lines are undetected.
- Priority: Low.

**No integration or UI tests exist:**
- What's not tested: End-to-end flow from `EKEventStoreChanged` notification through `SystemCalendarConnectionController` refresh → `SourceCoordinator` refresh → `ReminderEngine` reconcile. No UI/snapshot tests for `MenuBarContentView` or `SettingsView`.
- Risk: Interaction regressions between layers would only be caught manually.
- Priority: Medium for integration; Low for UI snapshots.

**`SettingsWindowController` / `SettingsWindowAccessor` have no tests:**
- What's not tested: Window registration lifecycle, repeated `updateNSView` calls, the `activateKnownWindow` race condition.
- Files: `MeetingCountdownApp/AppShell/SettingsWindowController.swift`
- Risk: The `updateNSView` over-activation concern described above is untestable without a test.
- Priority: Low (AppKit window management is hard to unit test).

---

## Architecture Inconsistencies

**`FeishuMeetingCountdownApp` app name vs. CalDAV-only scope:**
- Issue: The app struct is named `FeishuMeetingCountdownApp`, the bundle identifier is `com.luiszeng.meetingcountdown`, the scheme is `FeishuMeetingCountdown`, and the `AppLogger` subsystem is `com.luiszeng.meetingcountdown`. These identifiers are inconsistent with each other and the display name "Feishu Meeting Countdown".
- Files: `MeetingCountdownApp/AppShell/FeishuMeetingCountdownApp.swift` line 8; `project.yml` lines 22–23
- Impact: Inconsistent log filtering; confusing for contributors.
- Fix approach: Align identifier, subsystem, and display name on a single canonical string.

**`SystemCalendarMeetingSource.healthState()` duplicates logic in `refresh()`:**
- Issue: The authorization check and selected-calendar guard in `healthState()` (lines 39–59 of `SystemCalendarMeetingSource.swift`) are essentially repeated at the top of `refresh()` (lines 63–73). Any change to the health logic must be applied in both places.
- Files: `MeetingCountdownApp/SystemCalendarBridge/SystemCalendarMeetingSource.swift` lines 38–113
- Impact: Fragile — changes to health criteria can silently drift from refresh criteria.
- Fix approach: Extract shared pre-condition checks into a private helper or fold `healthState()` to call `refresh()` internally.

**Combine used for `ReminderEngine.bind()` but nowhere else:**
- Issue: `ReminderEngine` uses `AnyCancellable` / `Combine.sink` to observe `SourceCoordinator.$state` (line 125). All other cross-component communication uses direct async calls. This creates an asymmetry — one dependency pulled in only for this one subscriber.
- Files: `MeetingCountdownApp/ReminderEngine/ReminderEngine.swift` lines 2, 95, 122–130
- Impact: Adds Combine as an implicit dependency for the reminder layer; harder to test the subscription lifecycle directly.
- Fix approach: Replace with an `AsyncStream`/`AsyncPublisher` observation to be consistent with the rest of the Swift Concurrency pattern used throughout the codebase.

---

## Scalability Concerns

**24-hour lookahead with no pagination or count cap:**
- Problem: `SystemCalendarMeetingSource` fetches all events in a 24-hour window across all selected calendars with no limit on event count. On calendars with many events (e.g., shared team calendars), this may load hundreds of `EKEvent` objects.
- Files: `MeetingCountdownApp/SystemCalendarBridge/SystemCalendarMeetingSource.swift` line 28; `MeetingCountdownApp/SystemCalendarBridge/SystemCalendarAccess.swift` lines 74–96
- Current capacity: Works for typical personal calendars (< 20 events/day).
- Limit: Performance degrades on high-density calendars; main thread blocked during event enumeration.
- Scaling path: Add a cap (e.g., 50 events), move EventKit calls off main thread.

---

*Concerns audit: 2026-04-01*
