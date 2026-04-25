# JonesControl Tab Bar And Heating Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a two-tab app shell with `Garmin` and `Heating`, hide the tab bar with animation in landscape, and ship a first-pass local heating schedule editor with four visible slots and a simple detail editor.

**Architecture:** Split the current single-screen root into a small app shell that owns tab selection and orientation-driven tab bar visibility. Keep the Garmin launch/router flow intact inside its own feature view. Add a separate Heating feature with a local schedule model shaped to later export into the `xtura-automation` daily-period format, including derived hidden off periods at the start and end of day.

**Tech Stack:** SwiftUI, Observation, WebKit, XCTest/Swift Testing, iOS scene geometry/orientation APIs

---

## File Structure

- Modify: `JonesControl/ContentView.swift`
  - Reduce to a small root entry point or replace with the new app shell.
- Create: `JonesControl/AppShellView.swift`
  - Own selected tab, orientation tracking, and animated tab-bar visibility.
- Create: `JonesControl/GarminView.swift`
  - Host the existing router reachability/web view flow inside the Garmin tab.
- Create: `JonesControl/Heating/HeatingSchedule.swift`
  - Define the local four-slot schedule model, validation, and derived export/padding logic.
- Create: `JonesControl/Heating/HeatingView.swift`
  - Show the vertical slot list for the Heating tab.
- Create: `JonesControl/Heating/HeatingSlotEditorView.swift`
  - Edit a single visible slot.
- Create: `JonesControl/TabBarVisibilityModel.swift`
  - Small testable state helper for portrait/landscape tab-bar behavior.
- Modify: `JonesControl/JonesControlApp.swift`
  - Inject the new root shell while preserving the existing Garmin launch model wiring.
- Create: `JonesControlTests/TabBarVisibilityModelTests.swift`
  - Cover tab-bar visibility decisions.
- Create: `JonesControlTests/HeatingScheduleTests.swift`
  - Cover slot validation, hidden off-period derivation, and backend-friendly export shape.
- Create: `docs/heating-schedule-api.md`
  - Document the local schedule model, export format, and future adapter expectations so another Codex can consume it for `xtura-automation` integration.

---

### Task 1: Build The Root Tab Shell

**Files:**
- Modify: `JonesControl/ContentView.swift`
- Create: `JonesControl/AppShellView.swift`
- Create: `JonesControl/TabBarVisibilityModel.swift`
- Modify: `JonesControl/JonesControlApp.swift`
- Create: `JonesControlTests/TabBarVisibilityModelTests.swift`

- [ ] **Step 1: Write the failing tab-bar visibility tests**

`JonesControlTests/TabBarVisibilityModelTests.swift`

```swift
import Testing
@testable import JonesControl

struct TabBarVisibilityModelTests {
    @Test func portraitKeepsTabBarVisible() {
        let model = TabBarVisibilityModel()

        model.update(for: .portrait)

        #expect(model.isTabBarVisible)
    }

    @Test func landscapeHidesTabBar() {
        let model = TabBarVisibilityModel()

        model.update(for: .landscape)

        #expect(model.isTabBarVisible == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:JonesControlTests/TabBarVisibilityModelTests`

Expected: FAIL because `TabBarVisibilityModel` and the orientation abstraction do not exist yet.

- [ ] **Step 3: Implement the minimal shell and visibility model**

Create a tiny `TabBarVisibilityModel` that maps portrait to visible and landscape to hidden. Build `AppShellView` with:

- a `TabView` containing `Garmin` and `Heating`
- a selected-tab state
- a simple orientation observer
- animated application of `.toolbarVisibility(..., for: .tabBar)` or equivalent tab-bar visibility modifier driven by the model

Keep `ContentView` thin by delegating to `AppShellView`.

- [ ] **Step 4: Preserve Garmin behavior inside the new shell**

Move the current router/reachability UI into a dedicated `GarminView` and embed it as the first tab labeled `Garmin`.

- [ ] **Step 5: Run tests and a build**

Run:

- `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:JonesControlTests/TabBarVisibilityModelTests`
- `xcodebuild build -project JonesControl.xcodeproj -scheme JonesControl -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

Expected: PASS for the visibility tests and a successful build.

- [ ] **Step 6: Commit**

```bash
git add JonesControl/ContentView.swift JonesControl/AppShellView.swift JonesControl/TabBarVisibilityModel.swift JonesControl/GarminView.swift JonesControl/JonesControlApp.swift JonesControlTests/TabBarVisibilityModelTests.swift
git commit -m "feat: add tab shell with landscape tab bar behavior"
```

---

### Task 2: Add The Local Heating Schedule Model

**Files:**
- Create: `JonesControl/Heating/HeatingSchedule.swift`
- Create: `JonesControlTests/HeatingScheduleTests.swift`

- [ ] **Step 1: Write the failing model tests**

Cover:

- a valid `on` slot requires a target temperature
- an `off` slot clears/forbids a target temperature
- overlapping visible slots are rejected
- derived hidden periods include an off segment from midnight to the first slot when needed
- derived hidden periods include a trailing off segment to midnight when needed

Representative test shape:

```swift
import Foundation
import Testing
@testable import JonesControl

struct HeatingScheduleTests {
    @Test func exportAddsLeadingAndTrailingOffPeriods() throws {
        let schedule = try HeatingSchedule(
            slots: [
                .init(startMinutes: 360, endMinutes: 480, mode: .on, targetCelsius: 19),
                .init(startMinutes: 1080, endMinutes: 1320, mode: .off, targetCelsius: nil),
                .placeholder(at: 2),
                .placeholder(at: 3),
            ]
        )

        let periods = schedule.exportedPeriods()

        #expect(periods.first?.startMinutes == 0)
        #expect(periods.first?.mode == .off)
        #expect(periods.last?.mode == .off)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:JonesControlTests/HeatingScheduleTests`

Expected: FAIL because the heating schedule types do not exist yet.

- [ ] **Step 3: Implement the schedule model**

Create:

- `HeatingSchedule`
- `HeatingSlot`
- `HeatingMode`
- local validation errors
- normalization rules for target temperature
- a derived export that produces backend-friendly periods including hidden leading/trailing off periods

Keep the model local-only and in-memory for now. Shape it so a later adapter to `xtura-automation` will be straightforward.

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:JonesControlTests/HeatingScheduleTests`

Expected: PASS for schedule validation and export tests.

- [ ] **Step 5: Commit**

```bash
git add JonesControl/Heating/HeatingSchedule.swift JonesControlTests/HeatingScheduleTests.swift
git commit -m "feat: add local heating schedule model"
```

---

### Task 3: Build The Heating List Screen

**Files:**
- Create: `JonesControl/Heating/HeatingView.swift`
- Modify: `JonesControl/AppShellView.swift`
- Modify: `JonesControl/Heating/HeatingSchedule.swift`

- [ ] **Step 1: Write a failing smoke test for the seeded schedule**

Add a small test ensuring the default schedule exposes exactly four visible slots and that the list-facing formatting helpers produce stable output for one seeded row.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:JonesControlTests/HeatingScheduleTests`

Expected: FAIL because default seed/list formatting helpers do not exist yet.

- [ ] **Step 3: Implement the Heating list view**

Build `HeatingView` with:

- a local `@State` or injected `HeatingSchedule`
- a vertical `List` or `ScrollView`-based stack for the four visible slots
- row layout matching the requested shape as closely as practical:
  `Start - End    On|Off    Target?    >`
- conditional target text only for `on`
- navigation into the slot editor

Keep styling simple and native.

- [ ] **Step 4: Wire Heating into the second tab**

Add the `Heating` tab to the app shell and ensure Garmin remains the default selected tab.

- [ ] **Step 5: Run a build and focused tests**

Run:

- `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:JonesControlTests/HeatingScheduleTests`
- `xcodebuild build -project JonesControl.xcodeproj -scheme JonesControl -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

Expected: PASS plus successful build.

- [ ] **Step 6: Commit**

```bash
git add JonesControl/Heating/HeatingView.swift JonesControl/AppShellView.swift JonesControl/Heating/HeatingSchedule.swift
git commit -m "feat: add heating schedule list tab"
```

---

### Task 4: Add The Slot Editor

**Files:**
- Create: `JonesControl/Heating/HeatingSlotEditorView.swift`
- Modify: `JonesControl/Heating/HeatingView.swift`
- Modify: `JonesControl/Heating/HeatingSchedule.swift`
- Modify: `JonesControlTests/HeatingScheduleTests.swift`

- [ ] **Step 1: Write the failing edit-behavior tests**

Cover:

- switching a slot from `on` to `off` clears the target
- saving an `on` slot without a target is rejected
- editing a slot into overlap with another visible slot is rejected

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:JonesControlTests/HeatingScheduleTests`

Expected: FAIL because the edit/update helpers do not exist yet.

- [ ] **Step 3: Implement the editor**

Build a simple detail screen with:

- start time picker
- end time picker
- `on`/`off` control
- target temperature stepper or picker shown only for `on`
- save action that validates before writing back

Prefer standard SwiftUI form controls. Surface validation inline or via a simple error message.

- [ ] **Step 4: Hook navigation from the list rows**

Make the row disclosure push `HeatingSlotEditorView` for the tapped slot and write edits back into the shared local schedule state.

- [ ] **Step 5: Run tests and a build**

Run:

- `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:JonesControlTests/HeatingScheduleTests`
- `xcodebuild build -project JonesControl.xcodeproj -scheme JonesControl -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

Expected: PASS and successful build.

- [ ] **Step 6: Commit**

```bash
git add JonesControl/Heating/HeatingSlotEditorView.swift JonesControl/Heating/HeatingView.swift JonesControl/Heating/HeatingSchedule.swift JonesControlTests/HeatingScheduleTests.swift
git commit -m "feat: add heating slot editor"
```

---

### Task 5: Final Verification And Cleanup

**Files:**
- Review all modified feature files
- Create: `docs/heating-schedule-api.md`
- Confirm unrelated `JonesControl/Info.plist` changes remain untouched unless intentionally included later

- [ ] **Step 1: Run the full relevant test suite**

Run:

- `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:JonesControlTests/TabBarVisibilityModelTests`
- `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:JonesControlTests/HeatingScheduleTests`

- [ ] **Step 2: Run the app build**

Run:

- `xcodebuild build -project JonesControl.xcodeproj -scheme JonesControl -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

- [ ] **Step 3: Manual simulator verification**

Check:

- Garmin tab still loads the router screen flow
- tab bar is visible in portrait
- tab bar animates away in landscape and returns in portrait
- Heating shows four rows
- an `on` slot shows target temperature
- an `off` slot omits target temperature
- editing a slot updates the list correctly

- [ ] **Step 4: Prepare integration notes for later xtura work**

Write `docs/heating-schedule-api.md` with:

- the visible four-slot model
- validation rules
- exported period shape
- how hidden leading/trailing off periods are derived
- any intentional differences from `/Users/rog/Development/xtura-automation`
- a short example payload/structure another Codex can consume directly

- [ ] **Step 5: Final commit if needed**

```bash
git add JonesControl docs/superpowers/plans/2026-04-21-jonescontrol-tabbar-heating.md JonesControlTests
git commit -m "feat: add heating tab and schedule editor"
```

---

## Notes

- Keep Heating local-only in this pass. Do not add networking or direct reads from `/Users/rog/Development/xtura-automation`.
- Do not include the existing unrelated `JonesControl/Info.plist` change in feature commits unless the user explicitly asks.
- Prefer extracting small SwiftUI feature views over growing `ContentView.swift`.
- If the tab-bar animation API behaves differently across iOS versions, prefer the simplest native approach that gives a clear hide/show transition instead of custom tab chrome.

---

## Linked Slot Follow-Up

Heating behavior changed after implementation review. The current follow-up work replaces placeholder-style slots with a linked four-slot chain.

Revised requirements:

- remove the user-facing `empty` slot concept
- every visible slot is explicit `off` or `heat`
- the four visible slots are contiguous in time order
- every slot has a minimum duration of 15 minutes
- editing one slot boundary updates adjacent slots automatically
- large edits propagate across the visible chain to preserve continuity and minimum duration
- hidden leading/trailing `off` periods remain derived only during export

### Follow-Up Task A: Refactor The Schedule Model

**Files:**
- Modify: `JonesControl/Heating/HeatingSchedule.swift`
- Modify: `JonesControlTests/HeatingScheduleTests.swift`

- [ ] Remove placeholder/empty-slot semantics from the visible schedule model.
- [ ] Add linked boundary propagation helpers for start/end edits.
- [ ] Ensure slot boundary edits preserve continuity and a 15-minute minimum through propagation.
- [ ] Keep export derivation for optional leading/trailing hidden `off` periods.
- [ ] Add tests for single-step and multi-step propagation behavior.

### Follow-Up Task B: Update The Heating Editor And List

**Files:**
- Modify: `JonesControl/Heating/HeatingView.swift`
- Modify: `JonesControl/Heating/HeatingSlotEditorView.swift`
- Modify: `JonesControlTests/HeatingScheduleTests.swift`

- [ ] Remove `Empty` from the editor UI.
- [ ] Keep every visible row editable only as `off` or `heat`.
- [ ] Route start/end changes through the new linked-slot propagation logic.
- [ ] Respect slot-specific min/max constraints implied by the remaining visible slots.
- [ ] Keep target temperature behavior intact for `heat` slots.

### Follow-Up Task C: Update The App Mapping Note

**Files:**
- Modify: `docs/heating-schedule-app-mapping.md`

- [ ] Replace placeholder/empty-slot language with the linked four-slot chain model.

---

## Service And Settings Follow-Up

Heating is no longer local-only. The next phase connects the linked four-slot editor to the real heating service and adds a Settings tab.

Current requirements:

- the server is the source of truth
- if the service is unreachable, do not allow offline schedule editing
- Heating edits one synthetic all-days program only
- Settings stores the service base URL
- Settings can fetch runtime mode and send:
  - `Manual Off`
  - `Resume Schedule`

### Follow-Up Task D: Add Heating Service Client And Document Mapping

**Files:**
- Create: `JonesControl/Heating/HeatingService.swift`
- Create: `JonesControl/Heating/HeatingServiceModels.swift`
- Modify: `JonesControl/Heating/HeatingSchedule.swift`
- Modify: `JonesControlTests/HeatingScheduleTests.swift`
- Create: `JonesControlTests/HeatingServiceTests.swift`

- [ ] Add document models for:
  - schedule document
  - program
  - period
  - runtime mode
- [ ] Add API client methods for:
  - `GET /v1/automation/heating-schedule`
  - `PUT /v1/automation/heating-schedule`
  - `GET /v1/heating/mode`
  - `POST /v1/heating/mode/schedule`
  - `POST /v1/heating/mode/off`
- [ ] Add mapping between one all-days backend program and the linked four-slot app schedule.
- [ ] Surface unsupported server schedule shapes instead of guessing how to merge them.
- [ ] Add tests for document decoding/encoding, schedule mapping, `409` handling, and `400 validation_failed` handling.

### Follow-Up Task E: Add Settings Tab And Service Configuration

**Files:**
- Modify: `JonesControl/AppShellView.swift`
- Create: `JonesControl/Settings/SettingsView.swift`
- Create: `JonesControl/Settings/SettingsStore.swift`
- Modify: `JonesControlTests/TabBarVisibilityModelTests.swift` only if needed

- [ ] Add a third tab: `Settings`.
- [ ] Add base URL / host configuration UI.
- [ ] Persist the configured service URL locally for the app.
- [ ] Show the current runtime mode in Settings.
- [ ] Add `Manual Off` and `Resume Schedule` actions.
- [ ] Show transport/action errors in Settings.

### Follow-Up Task F: Wire Heating To The Real Service

**Files:**
- Modify: `JonesControl/Heating/HeatingView.swift`
- Modify: `JonesControl/Heating/HeatingSlotEditorView.swift`
- Modify: `JonesControl/Heating/HeatingSchedule.swift`
- Modify: `JonesControlTests/HeatingScheduleTests.swift`
- Modify: `docs/heating-schedule-app-mapping.md`

- [ ] Load the Heating screen from `GET /v1/automation/heating-schedule`.
- [ ] Disable editing until a successful server fetch completes.
- [ ] Keep the last fetched document and `revision` in memory while editing.
- [ ] Save edits back with full-document `PUT`.
- [ ] After save success, replace local state with the full response body.
- [ ] On `409`, refetch and show a retry message.
- [ ] On `400 validation_failed`, display server validation messages.
- [ ] On transport failure, keep editing disabled until the server can be reached again.
- [ ] Update the app-side mapping doc to reflect service-backed editing and runtime mode integration.

### Follow-Up Task G: Final Verification For Service Integration

**Files:**
- Review modified Heating and Settings files
- Review docs updates

- [ ] Run focused tests for:
  - `HeatingScheduleTests`
  - `HeatingServiceTests`
  - `TabBarVisibilityModelTests`
- [ ] Run app build:
  - `xcodebuild build -project JonesControl.xcodeproj -scheme JonesControl -destination 'generic/platform=iOS Simulator'`
- [ ] Manually verify:
  - Heating stays unavailable if the service URL is missing or unreachable
  - successful fetch enables schedule editing
  - schedule save hits the configured server URL
  - `Manual Off` changes runtime mode
  - `Resume Schedule` changes runtime mode back
