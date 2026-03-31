---
generated: 2026-04-01
focus: quality
---

# Coding Conventions

**Analysis Date:** 2026-04-01

## Language and Version

- Swift 6.0 (strict concurrency enabled via `SWIFT_VERSION: 6.0` in `project.yml`)
- All code compiles under Swift 6 strict concurrency rules; `Sendable` conformance is explicit throughout

## Naming Conventions

**Files:**
- PascalCase, one type per file, named after the primary type: `ReminderEngine.swift`, `SourceCoordinator.swift`, `MeetingRecord.swift`
- Protocol files named after the primary protocol they define: `SystemCalendarAccess.swift`, `PreferencesStore.swift`
- Model bundles group related types in one file when they form a tightly coupled set: `SystemCalendarModels.swift`, `DiagnosticsState.swift`, `ReminderState.swift`

**Types (classes, structs, enums, protocols):**
- PascalCase: `MeetingRecord`, `SourceCoordinator`, `ReminderEngine`, `SystemCalendarMeetingSource`
- Protocols use a gerund or noun describing capability: `MeetingSource`, `PreferencesStore`, `DiagnosticsProviding`, `DiagnosticChecking`, `DateProviding`, `NextMeetingSelecting`, `ReminderScheduling`, `ReminderAudioEngine`, `SystemCalendarAccessing`
- Concrete implementations follow `[Adjective/Modifier][Protocol]` or `[Domain][Protocol]` pattern: `DefaultNextMeetingSelector`, `UserDefaultsPreferencesStore`, `InMemoryPreferencesStore`, `EventKitSystemCalendarAccess`, `TaskReminderScheduler`, `GeneratedToneReminderAudioEngine`

**Functions and Methods:**
- camelCase: `selectNextMeeting(from:now:)`, `loadReminderPreferences()`, `fetchEventPayloads(start:end:calendarIDs:)`, `reconcile(with:)`, `triggerReminder(context:soundDuration:isMuted:)`
- Boolean queries use `is` / `has` prefix: `isRefreshing`, `isCancelled`, `isAllDay`, `isMuted`, `hasWarmedUp`, `hasStoredSelectedSystemCalendarIDs()`
- Async methods use present-tense verbs: `refresh(trigger:now:)`, `reconcile(with:)`, `bind(to:)`, `stopAll()`

**Variables and Properties:**
- camelCase throughout: `sourceCoordinator`, `reminderEngine`, `preferencesStore`, `lastTriggeredIdentity`, `scheduledReminderTask`
- Published state uses `state` as top-level name: `@Published private(set) var state: SourceCoordinatorState`, `@Published private(set) var state: ReminderState`
- Constants defined as `static let` inside a private `enum Keys` for `UserDefaults` keys with dot-notation strings: `"reminder_preferences.countdown_override_seconds"`

**Enums:**
- PascalCase cases using camelCase values: `case appLaunch`, `case manualRefresh`, `case notConfigured(message: String)`, `case ready(message: String)`
- Associated values use explicit labels: `case failed(message: String)`, `case playing(context: ScheduledReminderContext, startedAt: Date)`

## Code Style

**Indentation:**
- 4 spaces (standard Xcode default)

**Braces:**
- Opening brace on same line; closing brace on its own line
- Trailing closures use standard Swift trailing closure syntax

**Line Length:**
- No explicit limit enforced by tooling; lines stay under ~120 characters by convention

**Blank Lines:**
- One blank line between methods; two blank lines between major logical sections within a file
- No blank line after opening brace or before closing brace (single-statement exception applies)

**Access Control:**
- `private` used aggressively for internal helpers: `private let source`, `private func triggerReminder(...)`, `private func cancelOutstandingWork(...)`
- `private(set)` for published/observable state: `@Published private(set) var state`
- `nonisolated` used where cross-actor static access is needed: `nonisolated static func bootstrapSelectedSystemCalendarIDs(...)`
- Public surface is the minimum needed: only `let` stored properties and explicit `func` APIs

**Optionals:**
- `guard let` for early-exit defensive checks
- `if let` for inline optional binding with short bodies
- `??` for default fallbacks on short expressions

**Result builders (SwiftUI):**
- `@ViewBuilder` explicitly annotated on private view-returning functions: `private var caldavGuideGroup: some View`, `private func calendarRow(for:) -> some View`
- Views broken into named `@ViewBuilder` computed properties or private functions instead of one large `body`

**Static Formatters:**
- Date formatters declared as `private static let` lazy constants to avoid repeated allocation: `private static let absoluteFormatter: DateFormatter`, `private static let timeFormatter: DateFormatter`

## Import Organization

**Order:**
1. Apple system frameworks (alphabetical): `AVFoundation`, `AppKit`, `Combine`, `EventKit`, `Foundation`, `OSLog`, `SwiftUI`
2. No third-party packages exist; no local module imports

**Pattern:** Each file imports only what it directly uses. Framework imports are sparse — most files import only `Foundation`.

## Documentation and Comments

**Style:** Chinese-language inline comments throughout (project rule from `AGENTS.md`). Target audience is "someone unfamiliar with Swift syntax and Apple frameworks."

**File-level comments:** Every file opens with a `///` or `//` block describing the file's purpose, its module context, and relationship to other modules. Example from `MeetingRecord.swift`:
```swift
/// 这个文件承载应用的统一会议模型。
/// 设计重点不是一次性把所有来源字段搬全，而是定义提醒引擎真正依赖的最小公共集合
```

**Type-level comments:** All protocols, classes, structs, and enums carry `///` doc comments explaining responsibility, lifecycle, actor constraints, and design rationale.

**Method-level comments:** Required for any method with branching logic, state changes, async boundaries, or framework interaction. Pattern: explain "why this design" not just "what it does."

**Inline comments:** Block comment (`///`) above the code construct, not trailing. Used heavily inside `body` in SwiftUI views to explain layout decisions.

**Comment density rule:** Average 1 meaningful comment per 8–10 lines of effective code; state machines and concurrency boundaries exceed this.

## Error Handling

**Domain errors:** Typed `enum` conforming to `Error, Equatable, Sendable` with associated `message: String`: `MeetingSourceError.notConfigured(message:)`, `MeetingSourceError.unavailable(message:)`. Each case carries a user-readable string surfaced via `userFacingMessage` computed property.

**Catch pattern:** Layered do-catch — specific domain error first, then catch-all:
```swift
do {
    let snapshot = try await source.refresh(...)
    // success path
} catch let error as MeetingSourceError {
    switch error {
    case .notConfigured: ...
    case .unavailable: ...
    }
} catch {
    // generic fallback
    logger.error("...")
}
```

**Error propagation:** Internal helpers `throw` typed domain errors upward; the coordinator at the boundary converts them into `state` mutations with user-visible strings. UI never receives raw `Error` objects.

**`defer` usage:** Used to guarantee cleanup regardless of throw path:
```swift
defer {
    state.isRefreshing = false
}
```

**Ignored errors:** Swallowed only at `Task.sleep` cancellation boundaries with explicit explaining comment.

## Concurrency and Actor Usage

**Main actor:** `@MainActor` applied at class level for all `ObservableObject` types (`SourceCoordinator`, `ReminderEngine`), all `NSWindowController` subclasses, and all protocols bridging to EventKit (`SystemCalendarAccessing`). This is the dominant concurrency pattern.

**Actors:** `actor` keyword used for storage implementations requiring isolation from concurrent access: `InMemoryPreferencesStore`, `UserDefaultsPreferencesStore`.

**`Sendable`:** Consistently applied to value types crossing concurrency boundaries: structs, enums, and protocol existentials used as dependencies all declare `Sendable` conformance.

**`[weak self]` in closures:** Used in all `Task` and scheduler closures that capture `self`, with `guard let self` check at entry.

**`async/await`:** Protocol interfaces default to `async` even when current implementations are synchronous, to avoid future migration burden (explicit design decision in code comments).

## Protocol and Dependency Injection

**Pattern:** Protocol-first design throughout. All major dependencies are injected as `any Protocol` existentials rather than concrete types. Example:
```swift
private let source: any MeetingSource
private let nextMeetingSelector: any NextMeetingSelecting
private let dateProvider: any DateProviding
private let scheduler: any ReminderScheduling
```

**Constructor injection:** All dependencies injected via `init(...)`, never via property setters after construction (except `bind(to:)` for reactive connections).

**`autoRefreshOnStart` parameter:** Boolean init flag used to suppress side-effects during testing: `init(..., autoRefreshOnStart: Bool = true)`.

## Recurring Idioms

**State machines as enums with associated values:**
```swift
enum ReminderState: Equatable, Sendable {
    case idle(message: String)
    case scheduled(ScheduledReminderContext)
    case playing(context: ScheduledReminderContext, startedAt: Date)
    case disabled
    case failed(message: String)
}
```
Computed properties (`summary`, `detailLine`, `activeIdentity`) on the enum keep switch exhaustiveness at one location.

**Static factory methods on state types:**
```swift
static func initial(sourceDisplayName: String) -> SourceCoordinatorState
static let phaseZero = DiagnosticsSnapshot(...)
static let `default` = ReminderPreferences(...)
```

**`enum` as namespace for pure static logic:** `SystemCalendarEventNormalizer`, `AppContainer`, `Keys` (inside `UserDefaultsPreferencesStore`) — no instances, only `static func`/`static let`.

**`@unknown default` in EventKit switches:** Always present to handle future framework additions gracefully.

**`localizedStandardCompare` for user-visible string sorting.**

**`NSDataDetector` for URL extraction from freeform text** (`SystemCalendarModels.swift`).

---

*Convention analysis: 2026-04-01*
