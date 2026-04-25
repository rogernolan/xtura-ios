# JonesControl Tab Bar And Heating Design

## Goal

Add a two-tab app shell to `JonesControl` with:

- a `Garmin` tab for the existing router web view
- a `Heating` tab for a simple server-backed daily schedule editor

Then extend it to a three-tab shell by adding:

- a `Settings` tab for configuring the heating service endpoint and sending a separate manual-off command

The tab bar should be visible in portrait, animate away in landscape, and animate back in portrait.

## Scope

This design covers:

- app-level tab navigation
- tab bar visibility behavior for orientation changes
- a linked-slot heating schedule model and UI
- a simple slot list plus slot edit screen
- heating schedule fetch/save against the service API
- a Settings tab for base URL configuration and manual-off control

This design does not include:

- weekday-specific scheduling
- background schedule syncing or live event subscriptions
- advanced heating controls beyond four visible slots
- editing multiple backend programs directly

## Existing Context

`JonesControl` already has:

- a launch/foreground reachability flow for the Garmin router UI
- a `WKWebView`-based `Garmin` screen
- a small SwiftUI app structure with `ContentView` as the current root

The nearby `xtura-automation` project already models heating programs as daily periods with an explicit off state, and its scheduler expects a day to start from an off period at `00:00`. That matters because the iOS app should keep a local model that can later export into that shape without redesign.

## User Experience

### App Navigation

The root screen becomes a `TabView` with three tabs:

1. `Garmin`
2. `Heating`
3. `Settings`

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

### Settings Tab

The Settings tab contains:

- a text field for the heating service host/base URL
- status or error messaging for schedule fetch/save behavior
- current heating runtime mode display
- a `Manual Off` action
- a `Resume Schedule` action

The service is assumed to be reachable over Tailscale using plain HTTP, for example:

- `http://vanpi.tail1234.ts.net:8080`

The manual-off action is not encoded into the schedule document. It is a separate service operation using the runtime-mode API.

## Data Model

### Visible UI Model

The Heating tab stores exactly four editable visible slots in app memory while the editor is active.

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

The server is the source of truth. The local linked-slot model is only an in-memory editing projection of the last successfully fetched server document.

### Network Model

The app also keeps the last fetched heating schedule document from the service API, including:

- `timezone`
- `programs`
- `revision`

For the first networked version, the app edits only one synthetic all-days schedule:

- one enabled program
- days covering `mon` through `sun`

The UI does not expose multiple backend programs yet.

Editing availability rules:

- the app must fetch the server document successfully before enabling schedule editing
- if the service is unreachable, the app should not allow offline schedule edits
- unsaved local changes are not treated as durable state

The app also keeps the current heating runtime mode document from the service, including:

- effective mode: `schedule`, `off`, `manual`, or `boost`
- any associated runtime metadata returned by the API

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

This keeps the app model aligned with the backend model.

For service integration:

- the app fetches the full document
- the app maps one editable all-days program into the linked four-slot UI
- the app writes back a full replacement document with the last seen `revision`
- the app fetches the current heating runtime mode separately

## Screen Structure

### Root App Shell

The current root content should be split into:

- an app shell view that owns the selected tab and orientation-aware tab bar visibility
- a Garmin feature view
- a Heating feature view
- a Settings feature view

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

The edit screen writes back into the in-memory draft derived from the last fetched server document.

Key behavior:

- saving does not reject gap/overlap-causing edits as independent invalid states
- instead, the edited slot boundary propagates into adjacent visible slots to preserve continuity and the 15-minute minimum
- the UI should still surface errors for truly impossible edits, but normal boundary changes should resolve through propagation rather than failure

The first pass should prefer simple standard iOS controls over custom schedule widgets.

### Settings Screen

The Settings screen includes:

- editable base URL / host field
- fetch/apply behavior for connection settings
- current runtime mode summary
- a `Manual Off` button
- a `Resume Schedule` button
- user-facing feedback for:
  - transport errors
  - unsupported server schedule shapes
  - `409` revision conflicts
  - `400 validation_failed` responses
  - service unavailable / offline editing disabled state

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
- Settings feature view
  - owns heating service endpoint configuration and manual-off action
- Heating schedule model
  - owns four visible linked slots, validation, and export transformation
- Heating slot edit view
  - edits one slot at a time
- Heating schedule API client
  - fetches and saves the full schedule document
- Heating mode API client
  - fetches the current runtime mode and sends runtime mode commands
- Heating schedule mapper
  - converts between the server document/program shape and the app’s linked four-slot schedule

The key design principle is to separate:

- app shell concerns
- Garmin concerns
- Heating concerns
- schedule data logic
- network document and mapping logic

### Service API Integration

The current service contract is:

- `GET /v1/automation/heating-schedule`
- `PUT /v1/automation/heating-schedule`
- `GET /v1/heating/mode`
- `POST /v1/heating/mode/schedule`
- `POST /v1/heating/mode/off`

For the first version:

- Heating tab loads and saves one synthetic all-days schedule through the schedule document API
- Heating tab is editable only after a successful fetch from the configured server
- Settings loads and displays the current runtime mode
- `Manual Off` calls `POST /v1/heating/mode/off`
- `Resume Schedule` calls `POST /v1/heating/mode/schedule`

The app does not need manual-target or boost controls yet even though the API supports them.

## Error Handling And Validation

For the first pass:

- invalid slot edits should be prevented or surfaced inline in the edit screen
- boundary edits should auto-propagate through linked neighbors before surfacing failure
- mode/target mismatch should be corrected automatically where reasonable
- transport, conflict, and validation errors from the service should be shown explicitly
- unsupported server document shapes should be surfaced instead of guessed at
- runtime mode fetch/set failures should be surfaced separately from schedule save failures
- if the server cannot be reached, schedule editing should be disabled rather than falling back to offline local edits

Examples:

- switching a slot to `off` clears the target
- switching a slot to `on` requires a target before saving
- extending a slot end updates the next slot start
- if that change would shrink later slots below 15 minutes, later slot boundaries move as needed
- a `409` schedule revision conflict triggers refetch and user retry
- a `400 validation_failed` response displays the returned server messages
- a runtime-mode request failure leaves the saved schedule untouched and shows a transport/action error
- a schedule fetch failure leaves the Heating screen unavailable for editing until the server can be reached

Unsupported first-version server cases include:

- multiple backend programs that cannot be safely represented as one all-days linked schedule
- missing all-days coverage when the app would otherwise have to guess a merge strategy

## Testing

The implementation should include tests for:

- tab-shell state that decides whether the tab bar is shown in portrait vs landscape
- linked-slot propagation rules across adjacent visible slots
- enforcement of the 15-minute minimum duration
- hidden padding/off-period derivation from visible slots
- export transformation into a backend-friendly sequence of periods
- mapping between the server document and the linked four-slot app model
- API-client handling for success, `409`, and `400 validation_failed`
- runtime-mode client handling for current-mode fetch, manual off, and resume schedule

UI-specific edit interactions can remain lightly tested in the first pass if the model logic is covered well.

## Tradeoffs

This design keeps the Heating UI intentionally narrow even though it now talks to the real service.

Pros:

- simpler editor model
- lower risk than exposing the full backend program set
- easier to ship a clear first version around one all-days schedule

Cons:

- the app does not expose multiple backend programs yet
- unsupported server schedule shapes must be surfaced instead of merged automatically

That tradeoff is acceptable because the goal of this pass is to establish the app shell, service-backed schedule editing, and simple runtime controls without overbuilding the editor.

## Follow-Up Work

Likely next steps after this pass:

- persist the schedule
- support weekday-specific programs
- support multiple backend programs directly
- add manual target / boost controls if they prove useful
