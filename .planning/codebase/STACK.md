---
generated: 2026-04-01
focus: tech
---

# Technology Stack

**Analysis Date:** 2026-04-01

## Languages

**Primary:**
- Swift 6.0 — All application source code and tests (`MeetingCountdownApp/`, `MeetingCountdownAppTests/`)
  - Strict concurrency enabled (`SWIFT_VERSION: 6.0` in `project.yml`)

## Runtime

**Environment:**
- macOS 14.0+ (Sonoma) — minimum deployment target set in `project.yml` (`MACOSX_DEPLOYMENT_TARGET: "14.0"`)
- Native macOS process; no sandboxing enforced (`CODE_SIGNING_ALLOWED: NO`, `CODE_SIGNING_REQUIRED: NO` in `project.yml`)

**Package Manager:**
- None — no Swift Package Manager, CocoaPods, or Carthage dependencies detected
- No `Package.swift`, `Podfile`, or `Cartfile` present
- All dependencies are Apple system frameworks only

## Frameworks

**Core UI:**
- SwiftUI — primary UI framework; drives `MenuBarExtra`, `Settings` scene, all views in `MeetingCountdownApp/AppShell/`
- AppKit — used alongside SwiftUI for `NSApplication`, `NSWorkspace`, `NSWindow` access; imported in `MenuBarContentView.swift` and `SettingsView.swift`

**Calendar / Events:**
- EventKit — sole external-data framework; wraps `EKEventStore`, `EKEvent`, `EKCalendar`, `EKAuthorizationStatus`; all usage isolated to `MeetingCountdownApp/SystemCalendarBridge/SystemCalendarAccess.swift`

**Audio:**
- AVFoundation — used for programmatic tone generation and playback via `AVAudioEngine` and `AVAudioPlayerNode`; isolated to `MeetingCountdownApp/ReminderEngine/ReminderAudioEngine.swift`

**Reactive / Concurrency:**
- Combine — used in `ReminderEngine.swift` (`AnyCancellable`) for binding `SourceCoordinator` state changes
- Swift Concurrency (`async/await`, `Task`, `actor`) — used pervasively across all layers; `@MainActor` isolation on all UI-touching classes

**Logging:**
- OSLog (`os.Logger`) — structured system logging, wrapped in `MeetingCountdownApp/Shared/AppLogger.swift` with subsystem `com.luiszeng.meetingcountdown`

**Testing:**
- XCTest — unit test framework; test bundle target `FeishuMeetingCountdownTests` in `MeetingCountdownAppTests/`

## Build System

**Project Generation:**
- XcodeGen — `project.yml` at repo root is the source of truth for project structure; running `xcodegen generate` regenerates `MeetingCountdown.xcodeproj/project.pbxproj`
- `project.yml` defines both app target (`FeishuMeetingCountdown`) and test target (`FeishuMeetingCountdownTests`)

**Xcode Project:**
- `MeetingCountdown.xcodeproj` — generated artifact; `objectVersion = 77` (Xcode 15+)
- Code coverage data gathering enabled on the scheme (`gatherCoverageData: true` in `project.yml`)

**Build Settings (from `project.yml`):**
- `SWIFT_VERSION: 6.0`
- `MACOSX_DEPLOYMENT_TARGET: "14.0"`
- `MARKETING_VERSION: 0.1.0`
- `CURRENT_PROJECT_VERSION: 1`
- `PRODUCT_BUNDLE_IDENTIFIER: com.luiszeng.meetingcountdown`
- `INFOPLIST_KEY_LSUIElement: YES` — runs as a menu bar agent (no Dock icon)
- `GENERATE_INFOPLIST_FILE: YES` — Info.plist is generated at build time, not checked in

## Key Dependencies (System Frameworks Only)

| Framework | Version | Purpose |
|-----------|---------|---------|
| SwiftUI | macOS 14+ | All UI rendering (menu bar, settings) |
| AppKit | macOS 14+ | Window management, NSApplication control |
| EventKit | macOS 14+ | Read-only access to macOS Calendar events |
| AVFoundation | macOS 14+ | Programmatic audio tone generation |
| Combine | macOS 14+ | Reactive binding between coordinator and reminder engine |
| OSLog | macOS 14+ | Structured system logging |
| Foundation | macOS 14+ | Core types: Date, DateFormatter, UserDefaults, URL, Task |
| XCTest | macOS 14+ | Unit testing |

No third-party packages or external libraries are used.

## Configuration

**Preferences Persistence:**
- `UserDefaults` (standard suite) — used by `UserDefaultsPreferencesStore` in `MeetingCountdownApp/Preferences/PreferencesStore.swift`
- Keys: `reminder_preferences.countdown_override_seconds`, `reminder_preferences.global_reminder_enabled`, `reminder_preferences.is_muted`, `connection_preferences.selected_system_calendar_ids`

**Environment:**
- No `.env` files or environment variable configuration detected
- No build configuration files (no `xcconfig` files referenced in `project.yml`)

## Platform Requirements

**Development:**
- macOS with Xcode 15+ (project object version 77)
- XcodeGen installed to regenerate `project.pbxproj` after adding/removing files

**Production:**
- macOS 14.0 (Sonoma) or later
- User must grant full calendar access (`NSCalendarsFullAccessUsageDescription` in Info.plist)
- User must have added a Feishu CalDAV account to macOS Calendar app before the product is useful

---

*Stack analysis: 2026-04-01*
