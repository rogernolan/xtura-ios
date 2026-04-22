# JonesControl Tab Bar And Heating Design

## Goal

Add a two-tab app shell to `JonesControl` with:

- a `Garmin` tab for the existing router web view
- a `Heating` tab for a simple local daily schedule editor

The tab bar should be visible in portrait, animate away in landscape, and animate back in portrait.

## Scope

This design covers only:

- app-level tab navigation
- tab bar visibility behavior for orientation changes
- a local-only heating schedule model and UI
- a simple slot list plus slot edit screen

This design does not include:

- live integration with `/Users/rog/Development/xtura-automation`
- weekday-specific scheduling
- schedule syncing, background refresh, or persistence outside the app’s local state
- advanced heating controls beyond four visible slots

## Existing Context

`JonesControl` already has:

- a launch/foreground reachability flow for the Garmin router UI
- a `WKWebView`-based `Garmin` screen
- a small SwiftUI app structure with `ContentView` as the current root

The nearby `xtura-automation` project already models heating programs as daily periods with an explicit off state, and its scheduler expects a day to start from an off period at `00:00`. That matters because the iOS app should keep a local model that can later export into that shape without redesign.

## User Experience

### App Navigation

The root screen becomes a `TabView` with two tabs:

1. `Garmin`
2. `Heating`

The active tab remains selected even when the tab bar hides in landscape.

### Orientation Behavior

In portrait:

- the tab bar is visible

In landscape:

- the tab bar animates away
- the content expands to use the space

When rotating back to portrait:

- the tab bar animates back in

This behavior should feel like a deliberate app-level layout choice, not a separate navigation reset.

### Garmin Tab

The Garmin tab keeps the current web-view-based router UI behavior with no feature change beyond living inside the new tab shell.

### Heating Tab

The Heating tab shows a simple vertical list of four visible schedule slots.

Each row is displayed as:

`Start time - End time    On|Off    Target?    >`

Rules:

- `Target` is shown only when the slot is `On`
- `>` opens a detail/edit screen for that slot
- there is one schedule shared across every day
- every visible slot is explicit: `on` or `off`
- there is no user-facing `empty` slot state

The four visible slots behave as a linked chain. Editing one slot boundary adjusts adjacent visible slots so the schedule remains contiguous.

## Data Model

### Visible UI Model

The Heating tab stores exactly four editable visible slots in local app state.

Each slot contains:

- `id`
- `startTime`
- `endTime`
- `mode` (`on` or `off`)
- `targetCelsius` optional

Validation and invariants:

- `endTime` must be later than `startTime`
- `targetCelsius` must be present when mode is `on`
- `targetCelsius` must be absent when mode is `off`
- each slot has a minimum duration of 15 minutes
- visible slots are ordered in time
- visible slots are contiguous with no gaps
- visible slots do not overlap

The linked-slot rule is important:

- slot `n`’s end boundary is the next slot’s start boundary
- moving a slot boundary updates adjacent slot boundaries automatically
- if an edit would squeeze a later slot below 15 minutes, the change propagates through later slots until all visible slots remain valid
- the same rule applies in reverse when a start boundary change needs to affect earlier slots

This local model is the source of truth for the UI.

### Hidden Padding Periods

The backend-oriented model may still need “off from midnight to first visible slot” and “off from last visible slot to midnight,” but those are now purely derived export behavior rather than part of the visible schedule.

For this pass:

- hidden padding periods are not shown in the list UI
- a leading hidden `off` is derived only if slot 1 starts after `00:00`
- a trailing hidden `off` is derived only if slot 4 ends before `24:00`
- if the visible chain already covers the boundary, no hidden padding period is emitted there

### Export Shape For Later Integration

The local model should expose a transform that can later map into the `xtura-automation` concept of daily heating periods:

- off at `00:00` if needed
- visible slots translated into effective periods
- trailing off period to end the day if needed

Because the visible slots are contiguous, export is now mostly a translation of the linked chain plus optional leading/trailing hidden `off` periods when the visible schedule does not touch day boundaries.

This keeps the first implementation local while preserving a clean future path into the existing backend model.

## Screen Structure

### Root App Shell

The current root content should be split into:

- an app shell view that owns the selected tab and orientation-aware tab bar visibility
- a Garmin feature view
- a Heating feature view

This gives each feature a clear boundary and keeps `ContentView` from becoming a large mixed-responsibility file.

### Heating List Screen

The list screen shows:

- a simple title/header
- four rows in a vertical list or stack

Each row contains:

- formatted start and end times
- the on/off state
- target temperature when relevant
- disclosure affordance

Rows should be easy to scan quickly and should reflect a continuous schedule chain rather than independent, optionally-empty slots.

### Heating Edit Screen

Tapping a row opens a simple edit screen for that slot with:

- start time picker
- end time picker
- on/off picker or toggle
- target temperature control shown only when `on`

The edit screen writes back into local app state.

Key behavior:

- saving does not reject gap/overlap-causing edits as independent invalid states
- instead, the edited slot boundary propagates into adjacent visible slots to preserve continuity and the 15-minute minimum
- the UI should still surface errors for truly impossible edits, but normal boundary changes should resolve through propagation rather than failure

The first pass should prefer simple standard iOS controls over custom schedule widgets.

## Architecture

### Recommended File Boundaries

- `ContentView.swift`
  - reduced to the app shell entry point or replaced by a small root coordinator view
- new tab shell view
  - owns tab selection and orientation/tab-bar visibility behavior
- Garmin feature view
  - wraps the current Garmin launch/router UI
- Heating feature view
  - owns the schedule list screen
- Heating schedule model
  - owns four visible slots, validation, and export transformation
- Heating slot edit view
  - edits one slot at a time

The key design principle is to separate:

- app shell concerns
- Garmin concerns
- Heating concerns
- schedule data logic

## Error Handling And Validation

For the first pass:

- invalid slot edits should be prevented or surfaced inline in the edit screen
- boundary edits should auto-propagate through linked neighbors before surfacing failure
- mode/target mismatch should be corrected automatically where reasonable

Examples:

- switching a slot to `off` clears the target
- switching a slot to `on` requires a target before saving
- extending a slot end updates the next slot start
- if that change would shrink later slots below 15 minutes, later slot boundaries move as needed

No backend/network error handling is needed yet because Heating is local-only.

## Testing

The implementation should include tests for:

- tab-shell state that decides whether the tab bar is shown in portrait vs landscape
- linked-slot propagation rules across adjacent visible slots
- enforcement of the 15-minute minimum duration
- hidden padding/off-period derivation from visible slots
- export transformation into a backend-friendly sequence of periods

UI-specific edit interactions can remain lightly tested in the first pass if the model logic is covered well.

## Tradeoffs

This design intentionally keeps Heating local for now.

Pros:

- faster implementation
- lower risk
- easier to iterate on the UI before integrating the real service

Cons:

- no live sync with `xtura-automation` yet
- users can edit a schedule that does not yet affect the real heater

That tradeoff is acceptable because the goal of this pass is to establish the app shell and a clean local schedule-editing experience.

## Follow-Up Work

Likely next steps after this pass:

- connect the local Heating model to `xtura-automation`
- persist the schedule
- add schedule loading/saving and error states
- support weekday-specific programs
