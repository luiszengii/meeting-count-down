---
generated: 2026-04-01
focus: tech
---

# External Integrations

**Analysis Date:** 2026-04-01

## APIs & External Services

**None — No network calls or external API integrations are present.**

The app is intentionally offline-first. Meeting data is consumed from the local macOS Calendar database (already synced by the OS), not fetched directly over the network at runtime.

## Data Storage

**Preferences / Settings:**
- `UserDefaults` (standard suite) — sole persistence mechanism
  - Implementation: `UserDefaultsPreferencesStore` actor in `MeetingCountdownApp/Preferences/PreferencesStore.swift`
  - Stored keys: reminder countdown override seconds, global reminder enabled flag, muted flag, selected system calendar IDs
  - No migration strategy currently implemented; in-memory fallback (`InMemoryPreferencesStore`) used in tests

**Calendar Events:**
- macOS Calendar database — read-only via EventKit (`EKEventStore`)
  - Not a direct database connection; accessed through Apple's EventKit framework API
  - Requires user-granted `fullAccessToEvents` permission
  - No local caching layer; events are fetched fresh on each `refresh(trigger:)` call

**File Storage:**
- None — no files are written to disk by the app

**Caching:**
- None — no in-memory or disk cache for meeting data between refreshes

## Authentication & Identity

**macOS Calendar Permission (EventKit):**
- Type: macOS privacy permission (not OAuth)
- Implementation: `EventKitSystemCalendarAccess.requestReadAccess()` in `MeetingCountdownApp/SystemCalendarBridge/SystemCalendarAccess.swift`
- Request method: `EKEventStore.requestFullAccessToEvents()` — triggers system permission dialog
- Permission key in generated Info.plist: `NSCalendarsFullAccessUsageDescription`
- Permission string (Chinese): "Feishu Meeting Countdown 需要读取你在 macOS 日历中同步的飞书会议，用来计算下一场会议并在会前提醒。"
- States handled: `fullAccess`, `notDetermined`, `denied`, `restricted`, `writeOnly`, `unknown`

**No user accounts, OAuth, API keys, or tokens are managed by this app.**

## Feishu / Lark CalDAV Integration

**Integration type:** Indirect — the app does NOT connect to Feishu servers directly.

The integration path is:
1. User configures a Feishu CalDAV account in macOS Calendar app manually (server: `caldav.feishu.cn`)
2. macOS Calendar syncs events from Feishu to the local calendar database
3. This app reads those already-synced events from the local database via EventKit

**Detection of Feishu calendars:**
- `EventKitSystemCalendarAccess.shouldSuggestCalendar(sourceTitle:)` in `MeetingCountdownApp/SystemCalendarBridge/SystemCalendarAccess.swift` checks if a calendar's source title contains `"caldav.feishu.cn"` (case-insensitive) to mark it as a suggested default

**No Feishu/Lark SDK, API tokens, or OAuth flows are used.**

## Monitoring & Observability

**Logging:**
- OSLog (`os.Logger`) via `AppLogger` struct in `MeetingCountdownApp/Shared/AppLogger.swift`
- Subsystem: `com.luiszeng.meetingcountdown`
- Categories: `"SourceCoordinator"`, `"ReminderEngine"` (set at injection in `AppContainer.swift`)
- Log levels used: `.info`, `.error`
- All log messages marked `.public` for visibility in Console.app

**Error Tracking:**
- None — no crash reporting or remote error tracking service (e.g., Sentry, Crashlytics) integrated

**Analytics:**
- None

## CI/CD & Deployment

**Hosting:**
- Not determined — no deployment configuration files detected (no Fastlane, no GitHub Actions workflows, no `.xcode-version`)

**CI Pipeline:**
- None detected

**Code Signing:**
- Disabled in `project.yml`: `CODE_SIGNING_ALLOWED: NO`, `CODE_SIGNING_REQUIRED: NO`
- App is not currently configured for App Store or notarization distribution

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- None

## Communication Protocols

No network communication protocols are used. The app operates entirely on local system APIs:
- EventKit for calendar data (IPC to Calendar daemon, not a network protocol)
- UserDefaults for preferences (local plist storage)
- AVFoundation for audio output (local hardware)
- OSLog for logging (local system log)

## System Entitlements / Capabilities

**Calendar Access:**
- `NSCalendarsFullAccessUsageDescription` — required for EventKit read access

**Menu Bar Agent:**
- `INFOPLIST_KEY_LSUIElement: YES` — suppresses Dock icon; app runs as a background agent with menu bar presence only

**macOS Privacy Settings Deep Link:**
- `x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars` — used in `SettingsView.swift` to direct users to fix denied calendar permission

---

*Integration audit: 2026-04-01*
