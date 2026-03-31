---
generated: 2026-04-01
focus: arch
---

# Architecture

**Analysis Date:** 2026-04-01

## Pattern Overview

**Overall:** Layered MVVM with protocol-oriented dependency injection and a unidirectional data flow

**Key Characteristics:**
- Single macOS menu-bar app target (`FeishuMeetingCountdown`), no Swift Package modules yet
- All stateful objects (`SourceCoordinator`, `ReminderEngine`, `SystemCalendarConnectionController`) are `@MainActor`-bound `ObservableObject` classes; views only read published state and call `async` action methods
- Strict boundary between EventKit and the rest of the app: raw `EKEvent`/`EKCalendar` objects never escape `SystemCalendarBridge/`; every other layer works only with domain types (`MeetingRecord`, `SystemCalendarDescriptor`, etc.)
- Every externally-facing service is hidden behind a protocol (`MeetingSource`, `SystemCalendarAccessing`, `PreferencesStore`, `ReminderScheduling`, `ReminderAudioEngine`, `DateProviding`) so that tests can inject fakes without real system capabilities
- Concurrency: Swift 6 strict-concurrency mode; long-lived shared objects use `@MainActor`; persistent state stores use `actor`

## Layers

**AppShell (presentation & wiring):**
- Purpose: SwiftUI `App` entry point, scene declarations, dependency assembly, and thin views
- Location: `MeetingCountdownApp/AppShell/`
- Contains: `FeishuMeetingCountdownApp` (entry), `AppContainer` (DI factory), `AppRuntime` (shared-object bag), `MenuBarContentView`, `SettingsView`, `SettingsWindowController`
- Depends on: `SourceCoordinator`, `ReminderEngine`, `SystemCalendarConnectionController`, SwiftUI, AppKit
- Used by: SwiftUI runtime only; nothing else imports AppShell

**SourceCoordinator (state machine / aggregator):**
- Purpose: Single refresh entry point for the active `MeetingSource`; aggregates raw snapshots into `SourceCoordinatorState` which is the canonical UI-facing meeting state
- Location: `MeetingCountdownApp/SourceCoordinator/`
- Contains: `SourceCoordinator` (main state machine), `StubMeetingSource` (Phase-0 test double)
- Depends on: `Domain` protocols (`MeetingSource`, `NextMeetingSelecting`, `DateProviding`), `Shared/AppLogger`
- Used by: `AppShell` views (read-only via `@ObservedObject`), `ReminderEngine` (subscribes via Combine)

**ReminderEngine (reminder scheduling):**
- Purpose: Converts `SourceCoordinatorState.nextMeeting` into a real scheduled reminder; owns the full lifecycle of a single active reminder task (cancel → schedule → play audio → idle)
- Location: `MeetingCountdownApp/ReminderEngine/`
- Contains: `ReminderEngine` (state machine), `ReminderState` (value-type output), `ReminderAudioEngine` protocol + `GeneratedToneReminderAudioEngine` (AVFoundation implementation)
- Depends on: `Domain` types (`MeetingRecord`, `DateProviding`), `Preferences` (`PreferencesStore`), `Shared/AppLogger`; subscribes to `SourceCoordinator.$state` via Combine
- Used by: `AppShell` views (read-only `reminderEngine.state`)

**SystemCalendarBridge (EventKit adapter):**
- Purpose: The only place that imports `EventKit`; maps EK objects to app-owned models and provides calendar enumeration, authorization, event fetching, and change-notification handling
- Location: `MeetingCountdownApp/SystemCalendarBridge/`
- Contains: `SystemCalendarModels` (pure value types), `SystemCalendarAccess` (protocol + `EventKitSystemCalendarAccess`), `SystemCalendarConnectionController` (auth/selection state + `EKEventStoreChanged` listener), `SystemCalendarMeetingSource` (implements `MeetingSource`)
- Depends on: `EventKit`, `Domain`, `Preferences`
- Used by: `AppContainer` (assembles `SystemCalendarMeetingSource` and `SystemCalendarConnectionController`), `AppShell/SettingsView` (observes `SystemCalendarConnectionController`)

**Domain (pure model & rules):**
- Purpose: Platform-agnostic meeting model, data-source protocol, selection rules, and refresh taxonomy — no UI, no framework imports beyond Foundation
- Location: `MeetingCountdownApp/Domain/`
- Contains: `MeetingRecord` (canonical meeting value), `MeetingSource` protocol + `SourceSyncSnapshot`, `NextMeetingSelector` protocol + `DefaultNextMeetingSelector`, `RefreshTrigger` enum, `DateProviding` protocol + `SystemDateProvider`
- Depends on: Foundation only
- Used by: Every other layer; is the only layer not allowed to import anything else from the app

**Preferences (persistence):**
- Purpose: Non-sensitive user preferences model and async read/write protocol; hides storage details behind `PreferencesStore`
- Location: `MeetingCountdownApp/Preferences/`
- Contains: `ReminderPreferences` (value type), `PreferencesStore` protocol, `InMemoryPreferencesStore` (test double), `UserDefaultsPreferencesStore` (production)
- Depends on: Foundation only
- Used by: `SystemCalendarBridge`, `ReminderEngine`, `AppContainer`

**Diagnostics (read-only health checks):**
- Purpose: Samples system facts (currently just EventKit authorization) and formats them as structured `DiagnosticCheckStatus` values for display; never triggers permission prompts
- Location: `MeetingCountdownApp/Diagnostics/`
- Contains: `DiagnosticsState` (status enum + snapshot + item descriptors), `DiagnosticCheckers` (`DefaultDiagnosticsProvider`, `SystemCalendarPermissionDiagnostic`)
- Depends on: EventKit (read-only), Foundation
- Used by: Not yet wired to a live view; protocols allow test injection

**Shared (cross-cutting utilities):**
- Purpose: Utilities that do not belong to any single domain layer
- Location: `MeetingCountdownApp/Shared/`
- Contains: `AppLogger` (thin `OSLog` wrapper keyed by subsystem `com.luiszeng.meetingcountdown`)
- Depends on: Foundation, OSLog
- Used by: `SourceCoordinator`, `ReminderEngine`

## Data Flow

**Primary meeting pipeline (normal path):**

1. `AppContainer.makeAppRuntime()` assembles `EventKitSystemCalendarAccess` → `SystemCalendarMeetingSource` → `SourceCoordinator` on `@main` startup
2. `SourceCoordinator.init` fires `refresh(trigger: .appLaunch)` immediately
3. `SourceCoordinator.refresh` calls `source.refresh(trigger:now:)` on `SystemCalendarMeetingSource`
4. `SystemCalendarMeetingSource` calls `calendarAccess.fetchEventPayloads(...)` which invokes `EKEventStore.events(matching:)` internally
5. Raw `EKEvent` payloads are mapped to `SystemCalendarEventPayload` (pure Swift) → `SystemCalendarEventNormalizer.makeMeetingRecord(...)` → `[MeetingRecord]`
6. `SystemCalendarMeetingSource` returns `SourceSyncSnapshot` to `SourceCoordinator`
7. `SourceCoordinator` runs `nextMeetingSelector.selectNextMeeting(from:now:)` and publishes updated `SourceCoordinatorState` via `@Published`
8. `MenuBarContentView` and `SettingsView` re-render from the new state
9. `ReminderEngine` receives the `$state` Combine sink and calls `reconcile(with:)`, computing a new reminder schedule or cancelling the old one

**Calendar change-notification flow:**

1. macOS posts `EKEventStoreChanged` notification
2. `SystemCalendarConnectionController.registerEventStoreChangedObserver()` catches it on `.main`
3. Controller calls `refreshState()` to re-enumerate calendars, then calls `onCalendarConfigurationChanged(.systemCalendarChanged)`
4. The callback (injected via `AppContainer`) calls `sourceCoordinator.refresh(trigger: .systemCalendarChanged)`
5. Pipeline from step 3 above repeats

**Settings / user action flow:**

- User taps "授权访问日历" → `systemCalendarConnectionController.requestCalendarAccess()` → calls `calendarAccess.requestReadAccess()` → on success, calls `onCalendarConfigurationChanged(.manualRefresh)`
- User toggles a calendar checkbox → `setCalendarSelection(calendarID:isSelected:)` persists to `PreferencesStore`, then calls `onCalendarConfigurationChanged(.manualRefresh)`
- User taps "立即刷新" → `sourceCoordinator.refresh(trigger: .manualRefresh)` directly

**State Management:**

- `SourceCoordinatorState` (`struct`, value-semantic, `Equatable`): single source of truth for meeting state; published as `@Published` from `SourceCoordinator`
- `ReminderState` (`enum`, value-semantic, `Equatable`): published from `ReminderEngine`; transitions are: `idle` → `scheduled` → `playing` or `triggeredSilently` → `idle`
- `SystemCalendarConnectionController` owns `@Published` properties for auth, available calendars, selected IDs, loading/requesting booleans, and last error
- No global state container; objects are passed explicitly through `AppRuntime` and injected into views at the scene level

## Key Abstractions

**`MeetingSource` protocol:**
- Purpose: Uniform async interface for any calendar data provider
- Examples: `MeetingCountdownApp/Domain/MeetingSource.swift` (protocol), `MeetingCountdownApp/SystemCalendarBridge/SystemCalendarMeetingSource.swift` (production), `MeetingCountdownApp/SourceCoordinator/StubMeetingSource.swift` (test double)
- Pattern: Protocol with two async methods (`healthState()` and `refresh(trigger:now:)`); callers never see `EKEvent`

**`PreferencesStore` protocol:**
- Purpose: Async read/write for non-sensitive user preferences, decoupled from any specific storage
- Examples: `MeetingCountdownApp/Preferences/PreferencesStore.swift`; `InMemoryPreferencesStore` (actor, for tests), `UserDefaultsPreferencesStore` (actor, production)
- Pattern: Swift `actor`-based implementations ensure safe cross-async access

**`NextMeetingSelecting` protocol:**
- Purpose: Pluggable rule for picking the "next meeting" from a sorted list
- Examples: `MeetingCountdownApp/Domain/NextMeetingSelector.swift`; `DefaultNextMeetingSelector` filters `isAllDay`, `isCancelled`, and `startAt < now`

**`DateProviding` protocol:**
- Purpose: Injected clock so that business logic never calls `Date()` directly, enabling deterministic unit tests
- Examples: `MeetingCountdownApp/Domain/NextMeetingSelector.swift`; `SystemDateProvider` (production)

**`AppRuntime`:**
- Purpose: Lightweight bag that co-owns shared long-lived objects; passed into SwiftUI scenes as a single `@StateObject`, preventing re-creation
- Location: `MeetingCountdownApp/AppShell/AppRuntime.swift`

## Entry Points

**`@main FeishuMeetingCountdownApp`:**
- Location: `MeetingCountdownApp/AppShell/FeishuMeetingCountdownApp.swift`
- Triggers: macOS launches the app; `@main` struct is instantiated by the SwiftUI runtime
- Responsibilities: Creates `AppRuntime` (via `AppContainer.makeAppRuntime()`), declares `MenuBarExtra` and `Settings` scenes, injects `sourceCoordinator`, `reminderEngine`, and `settingsWindowController` into both scenes

**`AppContainer.makeAppRuntime()`:**
- Location: `MeetingCountdownApp/AppShell/AppContainer.swift`
- Triggers: Called once from `FeishuMeetingCountdownApp.init`
- Responsibilities: Composes the entire dependency graph: `EventKitSystemCalendarAccess` → `SystemCalendarMeetingSource` → `SourceCoordinator`; `UserDefaultsPreferencesStore` → `ReminderEngine` (bound to coordinator via Combine); `SystemCalendarConnectionController` (with callback to `sourceCoordinator.refresh`)

## Error Handling

**Strategy:** Domain errors flow up through typed throws; UI-facing error strings are resolved at the layer that understands the error; views only receive `String` summaries via published state

**Patterns:**
- `MeetingSourceError` (`notConfigured`, `unavailable`) — thrown by `MeetingSource.refresh`; caught in `SourceCoordinator.refresh` and converted to `SourceCoordinatorState.lastErrorMessage` + `healthState`
- `ReminderEngine.reconcile` wraps audio-engine calls in `do/catch`; failures become `ReminderState.failed(message:)`
- `SystemCalendarConnectionController` stores `lastErrorMessage: String?` for display; does not throw to callers
- Unexpected `Error` values in `SourceCoordinator.refresh` are caught by a broad `catch` block and also written to `lastErrorMessage`

## Cross-Cutting Concerns

**Logging:** `AppLogger` (wraps `OSLog.Logger`) with subsystem `com.luiszeng.meetingcountdown`; each long-lived object creates its own instance with a distinct category string (e.g., `"SourceCoordinator"`, `"ReminderEngine"`). Location: `MeetingCountdownApp/Shared/AppLogger.swift`

**Validation:** Done at the boundary where data enters the domain — `SystemCalendarEventNormalizer` normalizes titles and de-duplicates URLs before creating `MeetingRecord`. `DefaultNextMeetingSelector` applies the canonical "skip all-day, skip cancelled, skip past" filter.

**Authentication:** EventKit permission flow is gated entirely behind `SystemCalendarConnectionController.requestCalendarAccess()`, which is only called when the user explicitly taps the authorize button in `SettingsView`. The app never auto-requests permission.

**Concurrency discipline:** `@MainActor` on all `ObservableObject` classes; `actor` on `PreferencesStore` implementations; `Sendable` conformances on all value types passed across concurrency domains; Swift 6 strict-concurrency enforced at build time (`SWIFT_VERSION: 6.0`).

---

*Architecture analysis: 2026-04-01*
