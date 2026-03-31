---
generated: 2026-04-01
focus: quality
---

# Testing Patterns

**Analysis Date:** 2026-04-01

## Test Framework

**Runner:**
- XCTest (Apple native)
- Target: `FeishuMeetingCountdownTests` (bundle.unit-test), configured in `project.yml`
- Swift version: 6.0 (same as production target)

**Assertion library:**
- XCTest assertions (`XCTAssertEqual`, `XCTAssertNil`, `XCTAssertTrue`, `XCTFail`, `XCTUnwrap`)

**Import pattern:**
```swift
import Foundation
import XCTest
@testable import FeishuMeetingCountdown
```

**Run command (Xcode):**
- `Cmd+U` in Xcode, or `xcodebuild test -scheme FeishuMeetingCountdown`

**Coverage:**
- Coverage data collection enabled: `gatherCoverageData: true` in `project.yml` scheme config

## Test File Organization

**Location:**
- Separate top-level directory `MeetingCountdownAppTests/` mirroring the production `MeetingCountdownApp/` directory structure
- Each subdirectory corresponds to a production module directory

**Mirror structure:**
```
MeetingCountdownApp/              MeetingCountdownAppTests/
├── AppShell/                     (no tests — pure UI/shell)
├── Diagnostics/                  ├── Diagnostics/DiagnosticCheckersTests.swift
├── Domain/                       ├── Domain/NextMeetingSelectorTests.swift
├── OnboardingRouter/             ├── OnboardingRouter/ (empty — not yet implemented)
├── Preferences/                  ├── Preferences/PreferencesStoreTests.swift
├── ReminderEngine/               ├── ReminderEngine/ReminderEngineTests.swift
├── SourceCoordinator/            ├── SourceCoordinator/SourceCoordinatorTests.swift
└── SystemCalendarBridge/         └── SystemCalendarBridge/SystemCalendarBridgeTests.swift
```

**Naming:**
- Test files: `[SubjectType]Tests.swift`
- Test classes: `final class [SubjectType]Tests: XCTestCase`
- Test methods: `func test[WhatIsBeingTestedUnderWhatCondition]()` — descriptive, full sentence style:
  - `testReconcileSchedulesFutureMeetingUsingDefaultSoundDuration()`
  - `testConnectionControllerAutoSelectsSuggestedCalendarsOnFirstAuthorizedLoad()`
  - `testSelectorSkipsAllDayAndCancelledMeetings()`

## Types of Tests

**Unit tests (dominant type):**
- All 6 test files are unit tests targeting individual classes, structs, or enums in isolation
- Dependencies are replaced with test doubles; no real EventKit, UserDefaults (isolated suite), or AVFoundation used

**Integration tests:**
- Not present as a separate target; some tests in `SystemCalendarBridgeTests.swift` combine `SystemCalendarMeetingSource` + `StubSystemCalendarAccess` + `InMemoryPreferencesStore` + `SystemCalendarConnectionController` — lightweight integration within one actor context

**E2E / UI tests:**
- Not present

## Test Structure

**Suite organization:**
```swift
@MainActor
final class ReminderEngineTests: XCTestCase {
    func testSomeBehavior() async {
        // arrange
        let engine = makeEngine(now: fixedNow(), audioEngine: ..., scheduler: ...)
        // act
        await engine.reconcile(with: readyState(nextMeeting: ...))
        // assert
        guard case let .scheduled(context) = engine.state else {
            return XCTFail("Expected scheduled state, got \(engine.state)")
        }
        XCTAssertEqual(context.countdownSeconds, 4)
    }

    // factory helpers at bottom of class
    private func makeEngine(...) -> ReminderEngine { ... }
    private func fixedNow() -> Date { ... }
}
```

**`@MainActor` annotation:** Applied at class level for tests of `@MainActor`-bound types (`SourceCoordinatorTests`, `ReminderEngineTests`, `SystemCalendarBridgeTests`). Tests not involving main-actor types omit it (`NextMeetingSelectorTests`, `DiagnosticCheckersTests`, `PreferencesStoreTests`).

**`async` test methods:** Used throughout for any subject with `async` methods. Tests drive the full `async` call chain directly without dispatch tricks.

**Guard-pattern for state assertions:**
```swift
guard case let .scheduled(context) = engine.state else {
    return XCTFail("Expected scheduled state, got \(engine.state)")
}
XCTAssertEqual(context.countdownSeconds, 4)
```
This pattern avoids force-unwrapping while providing readable failure messages.

**`defer` for cleanup in persistence tests:**
```swift
defer {
    cleanupUserDefaults.removePersistentDomain(forName: suiteName)
}
```

## Mocking

**Approach:** Hand-written test doubles — no mocking framework used.

**Stub (returns preset data):**
- `StubMeetingSource` (`MeetingCountdownApp/SourceCoordinator/StubMeetingSource.swift`) — lives in production target, injected in coordinator tests
- `StubSystemCalendarAccess` (private, in `SystemCalendarBridgeTests.swift`) — replaces real EventKit access
- `StubDiagnosticsProvider` (`DiagnosticsState.swift`) — in production target for early-phase use

**Spy (records calls):**
- `SpyReminderAudioEngine` (private, in `ReminderEngineTests.swift`) — tracks `playCallCount` and `stopCallCount`

**Fake (alternate working implementation):**
- `InMemoryPreferencesStore` (production target, `PreferencesStore.swift`) — used in tests as a zero-persistence stand-in
- `TestReminderScheduler` (private, in `ReminderEngineTests.swift`) — replaces `Task.sleep` with manually-fireable tasks
- `FixedDateProvider` (private, duplicated in each test file that needs it) — returns a hardcoded `Date`

**Failing source:**
- `FailingMeetingSource` (private, in `SourceCoordinatorTests.swift`) — always throws a preset `MeetingSourceError`

**What to mock:**
- All I/O boundaries: EventKit (`SystemCalendarAccessing`), audio (`ReminderAudioEngine`), persistence (`PreferencesStore`), time (`DateProviding`)
- All scheduling/timer behavior (`ReminderScheduling`)
- External sources (`MeetingSource`)

**What NOT to mock:**
- Domain logic under test: `DefaultNextMeetingSelector`, `SystemCalendarEventNormalizer`, `UserDefaultsPreferencesStore` (tested with isolated `suiteName`)
- The orchestration under test itself: coordinators/engines are constructed with real implementations of their own logic

## Fixtures and Factories

**Test factories pattern:** Each test class defines `private func make[Subject](...)` and `private func make[Entity](...)` helpers at the bottom of the class, keeping the test method body focused on the scenario:

```swift
// ReminderEngineTests.swift
private func makeEngine(
    now: Date,
    audioEngine: SpyReminderAudioEngine,
    scheduler: TestReminderScheduler,
    reminderPreferences: ReminderPreferences = .default
) -> ReminderEngine { ... }

private func readyState(nextMeeting: MeetingRecord?) -> SourceCoordinatorState { ... }

private func meeting(id: String, now: Date, offsetSeconds: Int) -> MeetingRecord { ... }

private func fixedNow() -> Date { ... }
```

```swift
// SourceCoordinatorTests.swift
private func descriptor() -> MeetingSourceDescriptor { ... }
private func meeting(id: String, now: Date, offsetMinutes: Int) -> MeetingRecord { ... }
private func fixedNow() -> Date { ... }
```

**Fixed time:** Every test class that involves time-sensitive logic defines its own `private func fixedNow() -> Date` returning a hardcoded `DateComponents` date, avoiding real-clock dependency. Dates are chosen explicitly (e.g., `2026-03-30 09:00`, `2026-04-01 09:00`).

**Default parameter values:** Production `static let default` and default init parameters used to reduce factory verbosity in tests: `ReminderPreferences.default`, `MeetingRecord(id:title:startAt:endAt:source:)` with optional fields defaulting.

**Shared descriptors:** `MeetingSourceDescriptor` and test calendar descriptors are created once per test class via a `private func descriptor()` or `private let calendarSource` field.

## Test-Specific Infrastructure (In-Production Target)

Several test doubles live in the **production target** by design, to be available as dependency injection options:

- `InMemoryPreferencesStore` — `MeetingCountdownApp/Preferences/PreferencesStore.swift`
- `StubMeetingSource` — `MeetingCountdownApp/SourceCoordinator/StubMeetingSource.swift`
- `StubDiagnosticsProvider` — `MeetingCountdownApp/Diagnostics/DiagnosticsState.swift`
- `SystemDateProvider` — `MeetingCountdownApp/Domain/NextMeetingSelector.swift` (real clock, not a stub, but swappable via protocol)

## `TestReminderScheduler` — Manual Task Control

The most elaborate test infrastructure in the codebase. Defined privately in `ReminderEngineTests.swift`:

```swift
@MainActor
private final class TestReminderScheduler: ReminderScheduling {
    private(set) var tasks: [ScheduledTask] = []

    var activeTasks: [ScheduledTask] {
        tasks.filter { !$0.isCancelled && !$0.hasFired }
    }

    func fireNextActiveTask() async { ... }
}
```

Allows tests to advance scheduler time explicitly without `Task.sleep`, making timing assertions deterministic. Tests verify task count, delay value, and cancellation state directly.

## Coverage Assessment

**Well-covered modules:**
- `Domain/NextMeetingSelector` — 3 focused tests covering empty input, filtering, and selection order
- `ReminderEngine` — 7 tests covering scheduling, immediate trigger, mute, global disable, deduplication, cancellation, and playback completion
- `SourceCoordinator` — 4 tests covering successful refresh, menubar title switching, domain error mapping, and unconfigured state
- `SystemCalendarBridge` — 6 tests covering suggestion logic, auto-selection, explicit-empty-selection guard, persistence, unconfigured source state, normalization, and link deduplication
- `Preferences/PreferencesStore` — 1 test covering `UserDefaults` round-trip for calendar IDs
- `Diagnostics` — 1 test covering `fullAccess` → `passed` mapping

**Low / no coverage:**
- `AppShell/` — `AppContainer`, `AppRuntime`, `FeishuMeetingCountdownApp`, `MenuBarContentView`, `SettingsView`, `SettingsWindowController` — zero tests (UI/shell layer intentionally untested)
- `OnboardingRouter/` — directory exists in both production and test target but contains no Swift files (not yet implemented)
- `ReminderEngine/ReminderAudioEngine.swift` — `GeneratedToneReminderAudioEngine` is not tested (replaced entirely by `SpyReminderAudioEngine`)
- `SystemCalendarConnectionController` — tested indirectly through `SystemCalendarBridgeTests`; its full state machine (authorization request flow, error handling, `autoRefreshOnStart`) is not exhaustively covered
- `DiagnosticsState` enums and computed properties (e.g., `summary`, `badgeText`, `symbolName`) — no direct tests
- Error paths in `SystemCalendarMeetingSource.refresh` for `calendarAccess.fetchEventPayloads` throwing non-`MeetingSourceError` errors

## CI/CD Integration

- No CI configuration detected (no `.github/`, `.circleci/`, `Fastfile`, etc.)
- Project uses `xcodegen` (`project.yml`) for Xcode project generation; tests run via standard Xcode scheme
- Coverage collection is enabled in the scheme (`gatherCoverageData: true`) but no minimum threshold is enforced

## Key Patterns Summary

| Pattern | Usage |
|---------|-------|
| Fixed-time injection via `DateProviding` | All timing-sensitive tests |
| `InMemoryPreferencesStore` as test stand-in | Coordinator, engine, bridge tests |
| Hand-written spies for call-count verification | `SpyReminderAudioEngine` |
| Manually-fireable scheduler | `TestReminderScheduler.fireNextActiveTask()` |
| Stub sources with preset data | `StubMeetingSource`, `StubSystemCalendarAccess`, `FailingMeetingSource` |
| Guard + `XCTFail` for enum state assertions | All state machine tests |
| `@testable import FeishuMeetingCountdown` | All test files |
| `@MainActor` class-level for main-actor subjects | Coordinator, engine, bridge tests |
| Isolated `UserDefaults` suite | `PreferencesStoreTests` |

---

*Testing analysis: 2026-04-01*
