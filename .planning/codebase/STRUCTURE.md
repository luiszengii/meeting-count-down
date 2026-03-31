---
generated: 2026-04-01
focus: arch
---

# Codebase Structure

**Analysis Date:** 2026-04-01

## Directory Layout

```
meeting-count-down/                     # Repo root
├── project.yml                         # XcodeGen project spec (source of truth for .xcodeproj)
├── MeetingCountdown.xcodeproj/         # Generated Xcode project (do NOT edit by hand)
├── MeetingCountdownApp/                # Single app-target source root
│   ├── AGENTS.md                       # Module-level AI agent instructions
│   ├── AppShell/                       # Entry point, DI, scenes, thin views
│   ├── Domain/                         # Pure business model & protocols (no framework imports)
│   ├── SourceCoordinator/              # Meeting-state aggregator and refresh entry point
│   ├── ReminderEngine/                 # Reminder scheduling, audio, and state machine
│   ├── SystemCalendarBridge/           # EventKit adapter — only place EK types live
│   ├── Preferences/                    # User preference models and persistence protocol
│   ├── Diagnostics/                    # Read-only health-check state and checkers
│   ├── Shared/                         # Cross-cutting utilities (logging)
│   └── OnboardingRouter/               # Placeholder directory (not yet populated)
├── MeetingCountdownAppTests/           # Unit-test target (mirrors app source structure)
│   ├── AGENTS.md
│   ├── Domain/
│   ├── SourceCoordinator/
│   ├── ReminderEngine/
│   ├── SystemCalendarBridge/
│   ├── Preferences/
│   ├── Diagnostics/
│   └── OnboardingRouter/
├── docs/                               # Human-authored documentation
│   ├── adrs/                           # Architecture Decision Records
│   ├── dev-logs/                       # Daily development logs
│   ├── pitfalls/                       # Documented gotchas and workarounds
│   └── templates/                      # Reusable doc templates
└── .planning/                          # AI-generated planning artifacts
    └── codebase/                       # Codebase-map documents (this file)
```

## Directory Purposes

**`MeetingCountdownApp/AppShell/`:**
- Purpose: Application shell — everything the macOS process needs to start and present UI
- Contains: `FeishuMeetingCountdownApp.swift` (entry), `AppContainer.swift` (DI factory), `AppRuntime.swift` (shared-object holder), `MenuBarContentView.swift`, `SettingsView.swift`, `SettingsWindowController.swift`
- Key files: `AppContainer.swift` (single place all dependencies are wired), `FeishuMeetingCountdownApp.swift` (scene declarations)

**`MeetingCountdownApp/Domain/`:**
- Purpose: Platform-agnostic domain model; no UIKit/AppKit/EventKit imports
- Contains: `MeetingRecord.swift`, `MeetingSource.swift`, `NextMeetingSelector.swift`, `RefreshTrigger.swift`
- Key files: `MeetingRecord.swift` (canonical meeting struct), `MeetingSource.swift` (protocol + health state + sync snapshot)

**`MeetingCountdownApp/SourceCoordinator/`:**
- Purpose: Aggregates raw `SourceSyncSnapshot` into `SourceCoordinatorState`; owns the single `refresh(trigger:)` entry point used by views and system-event handlers
- Contains: `SourceCoordinator.swift`, `StubMeetingSource.swift`
- Key files: `SourceCoordinator.swift`

**`MeetingCountdownApp/ReminderEngine/`:**
- Purpose: Converts `nextMeeting` from `SourceCoordinatorState` into a real scheduled audio reminder
- Contains: `ReminderEngine.swift`, `ReminderState.swift`, `ReminderAudioEngine.swift`
- Key files: `ReminderEngine.swift` (state machine), `ReminderAudioEngine.swift` (AVFoundation adapter protocol + `GeneratedToneReminderAudioEngine`)

**`MeetingCountdownApp/SystemCalendarBridge/`:**
- Purpose: EventKit isolation boundary; the only directory that imports `EventKit`
- Contains: `SystemCalendarModels.swift`, `SystemCalendarAccess.swift`, `SystemCalendarConnectionController.swift`, `SystemCalendarMeetingSource.swift`
- Key files: `SystemCalendarAccess.swift` (protocol + `EventKitSystemCalendarAccess`), `SystemCalendarConnectionController.swift` (manages auth, calendar selection, EKEventStoreChanged)

**`MeetingCountdownApp/Preferences/`:**
- Purpose: Non-sensitive user preferences; persistence details hidden behind protocol
- Contains: `ReminderPreferences.swift`, `PreferencesStore.swift` (protocol + `InMemoryPreferencesStore` + `UserDefaultsPreferencesStore`)
- Key files: `PreferencesStore.swift`

**`MeetingCountdownApp/Diagnostics/`:**
- Purpose: Read-only health checks; maps raw system facts to structured diagnostic status values for display
- Contains: `DiagnosticsState.swift`, `DiagnosticCheckers.swift`
- Key files: `DiagnosticsState.swift` (all status enums and snapshot)

**`MeetingCountdownApp/Shared/`:**
- Purpose: Utilities shared across all other directories; currently just the logger
- Contains: `AppLogger.swift`

**`MeetingCountdownAppTests/`:**
- Purpose: Unit-test target; directory tree mirrors `MeetingCountdownApp/` module-for-module
- Each test subdirectory contains its own `AGENTS.md` describing test scope
- Key files: `ReminderEngine/ReminderEngineTests.swift`, `Domain/NextMeetingSelectorTests.swift`, `SourceCoordinator/SourceCoordinatorTests.swift`, `SystemCalendarBridge/SystemCalendarBridgeTests.swift`

**`docs/adrs/`:**
- Purpose: Architecture Decision Records documenting key technical choices
- Notable ADRs: `2026-03-31-caldav-only-product-scope.md` (why only CalDAV), `2026-03-30-single-app-target-bootstrap.md`, `2026-03-30-bump-minimum-macos-to-14.md`, `2026-03-30-onboarding-routes-through-settings-window.md`

## Key File Locations

**Entry Points:**
- `MeetingCountdownApp/AppShell/FeishuMeetingCountdownApp.swift`: `@main` App struct; declares `MenuBarExtra` and `Settings` scenes
- `MeetingCountdownApp/AppShell/AppContainer.swift`: Dependency-injection factory; call `AppContainer.makeAppRuntime()` to see the full wiring

**Configuration:**
- `project.yml`: XcodeGen spec; defines targets, deployment target (macOS 14), Swift version (6.0), bundle ID (`com.luiszeng.meetingcountdown`), and Info.plist keys (`LSUIElement: YES` for menu-bar-only)
- `MeetingCountdown.xcodeproj/`: Generated from `project.yml`; regenerate with XcodeGen after adding files

**Core Logic:**
- `MeetingCountdownApp/SourceCoordinator/SourceCoordinator.swift`: Main meeting-state machine; start here to understand runtime behavior
- `MeetingCountdownApp/ReminderEngine/ReminderEngine.swift`: Reminder scheduling state machine
- `MeetingCountdownApp/SystemCalendarBridge/SystemCalendarConnectionController.swift`: Calendar auth and selection management
- `MeetingCountdownApp/Domain/MeetingRecord.swift`: Canonical data model consumed by all layers

**Testing:**
- `MeetingCountdownAppTests/` mirrors `MeetingCountdownApp/`; test file for module `X` lives at `MeetingCountdownAppTests/X/XTests.swift`

## Naming Conventions

**Files:**
- One primary type per file; file name matches the primary type name exactly: `SourceCoordinator.swift` contains `SourceCoordinator`, `ReminderState.swift` contains `ReminderState`
- Model/state files that define multiple related types use a plural or collective noun: `SystemCalendarModels.swift`, `DiagnosticCheckers.swift`
- Test files append `Tests` suffix: `ReminderEngineTests.swift`

**Directories:**
- PascalCase, named after the module/layer: `AppShell`, `SourceCoordinator`, `SystemCalendarBridge`
- Test directory mirrors source directory names exactly

**Types:**
- `PascalCase` for all Swift types
- Protocols describing capabilities use noun phrases: `MeetingSource`, `PreferencesStore`, `SystemCalendarAccessing`; or `-ing` gerund: `NextMeetingSelecting`, `ReminderScheduling`, `DiagnosticsProviding`
- Concrete implementations prefix with context: `EventKitSystemCalendarAccess`, `UserDefaultsPreferencesStore`, `DefaultNextMeetingSelector`, `TaskReminderScheduler`
- State value types use `State` suffix: `SourceCoordinatorState`, `ReminderState`
- Snapshot value types use `Snapshot` suffix: `SourceSyncSnapshot`, `DiagnosticsSnapshot`

**Enums:**
- Case names are `camelCase`; cases carry payloads using labeled associated values: `.unconfigured(message: String)`, `.playing(context:, startedAt:)`
- Error enums adopt `Error` suffix: `MeetingSourceError`

## Where to Add New Code

**New calendar/data source integration:**
- Add a new `MeetingSource` conformance inside `MeetingCountdownApp/SystemCalendarBridge/` or a new sibling bridge directory
- Model types that must not escape the bridge live inside the bridge directory
- Wire into `AppContainer.makeAppRuntime()` and pass to `SourceCoordinator`

**New reminder behavior:**
- Extend `ReminderPreferences` in `MeetingCountdownApp/Preferences/ReminderPreferences.swift`
- Extend `ReminderState` cases in `MeetingCountdownApp/ReminderEngine/ReminderState.swift`
- Add scheduling logic inside `ReminderEngine.reconcile` in `MeetingCountdownApp/ReminderEngine/ReminderEngine.swift`

**New UI section in the menu bar or settings:**
- Keep logic in the relevant `ObservableObject`; add only rendering code to `MenuBarContentView.swift` or `SettingsView.swift`
- Do not add new `@StateObject` creations inside views; pass objects through from `AppRuntime` via `AppContainer`

**New domain rule or filter:**
- Add a new protocol in `MeetingCountdownApp/Domain/`
- Inject the protocol into `SourceCoordinator` or `ReminderEngine` as a dependency; do not hard-code in the layer

**New diagnostic check:**
- Implement `DiagnosticChecking` in `MeetingCountdownApp/Diagnostics/DiagnosticCheckers.swift`
- Add a new field to `DiagnosticsSnapshot` in `MeetingCountdownApp/Diagnostics/DiagnosticsState.swift`

**New utility:**
- Only use `MeetingCountdownApp/Shared/` for utilities that are truly cross-cutting (e.g., logging)
- Module-specific helpers belong in the module directory, not `Shared/`

**New tests:**
- Mirror the source directory path: source at `MeetingCountdownApp/X/Y.swift` → test at `MeetingCountdownAppTests/X/YTests.swift`
- Add an `AGENTS.md` to the test subdirectory if the test directory is new

## Special Directories

**`.planning/codebase/`:**
- Purpose: AI-generated codebase analysis documents
- Generated: Yes (by AI mapping agents)
- Committed: Yes

**`docs/`:**
- Purpose: Human-authored ADRs, dev logs, pitfall notes, and doc templates
- Generated: No
- Committed: Yes; all ADR and pitfall documents must be committed

**`MeetingCountdown.xcodeproj/`:**
- Purpose: Xcode project file generated by XcodeGen from `project.yml`
- Generated: Yes (run `xcodegen generate` from repo root after editing `project.yml` or adding Swift files)
- Committed: Yes (required for CI and Xcode to open the project)

**`MeetingCountdownApp/OnboardingRouter/`:**
- Purpose: Placeholder for future onboarding routing logic
- Generated: No
- Committed: Yes (directory with `AGENTS.md` only; no Swift files yet)

---

*Structure analysis: 2026-04-01*
