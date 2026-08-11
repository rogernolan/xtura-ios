# Variable Heating Slots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let JonesControl load, edit, add, delete, and save any valid number of periods in its single everyday heating program.

**Architecture:** Replace the fixed four-slot `HeatingSchedule` invariant with a contiguous variable-length range model. Keep the server-required midnight range as an anchor; structural operations transform adjacent ranges locally, then the existing feature model saves the full period document with optimistic revision handling.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, Xcode project.

## Global Constraints

- Change JonesControl only; do not change xtura-automation or its web UI.
- Continue to support exactly one enabled program covering all seven days.
- Preserve every imported server period, including adjacent equal effective states.
- The first period starts at `00:00`; the final range ends at minute `1440`.
- Retain a 15-minute minimum range duration.
- A newly added range defaults to Off.

---

### Task 1: Make the schedule model variable length and lossless

**Files:**

- Modify: `JonesControl/Heating/HeatingSchedule.swift`
- Modify: `JonesControlTests/HeatingScheduleTests.swift`

**Interfaces:**

- Produces: `HeatingSchedule(activeSlots:)` accepting one or more contiguous slots.
- Produces: direct server mapping through `init(serverProgram:)` and `serverDocument(timezone:revision:programID:)` without padding or deduplication.

- [ ] **Step 1: Write the failing mapping tests**

Add a five-period document with the live shape and assert import/export equality:

~~~swift
let periods = [
    HeatingSchedulePeriod(start: "00:00", mode: .off),
    HeatingSchedulePeriod(start: "05:30", mode: .heat, targetCelsius: 6),
    HeatingSchedulePeriod(start: "06:00", mode: .heat, targetCelsius: 5),
    HeatingSchedulePeriod(start: "07:00", mode: .off),
    HeatingSchedulePeriod(start: "09:00", mode: .off)
]
#expect(try HeatingSchedule(serverProgram: program).serverDocument(...) == document)
~~~

- [ ] **Step 2: Run the focused mapping test and verify it fails**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:JonesControlTests/HeatingScheduleTests`

Expected: the five-period import fails with `incompatibleShape`.

- [ ] **Step 3: Replace the four-slot invariant**

Remove `visibleSlotCount`, make both initializers require `!slots.isEmpty`, and validate contiguous full-day ranges. Remove `paddingToVisibleSlotCount`; import each server period directly and export one period per stored range, preserving consecutive equal modes.

- [ ] **Step 4: Run the focused tests and verify they pass**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:JonesControlTests/HeatingScheduleTests`

Expected: PASS.

- [ ] **Step 5: Commit**

~~~bash
git add JonesControl/Heating/HeatingSchedule.swift JonesControlTests/HeatingScheduleTests.swift
git commit -m "Support variable heating schedule periods"
~~~

### Task 2: Add structural schedule operations

**Files:**

- Modify: `JonesControl/Heating/HeatingSchedule.swift`
- Modify: `JonesControlTests/HeatingScheduleTests.swift`

**Interfaces:**

- Produces: `func addingOffSlot(after index: Int) -> Result<HeatingSchedule, HeatingScheduleUpdateError>`.
- Produces: `func deletingSlot(at index: Int) -> Result<HeatingSchedule, HeatingScheduleUpdateError>`.

- [ ] **Step 1: Write failing structural-operation tests**

Test that splitting a 06:00–08:00 heat range makes 06:00–07:00 heat and 07:00–08:00 off; test that a 15-minute range cannot split; test that deleting the second range extends the midnight anchor through it; and test that deleting index zero fails.

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:JonesControlTests/HeatingScheduleTests`

Expected: compiler errors for the missing operation methods.

- [ ] **Step 3: Implement structural operations**

Split the selected slot at its 15-minute-aligned midpoint only when both halves meet the minimum duration; leave the first half unchanged and insert an Off second half. Delete only indexes greater than zero by extending the preceding slot to the deleted slot's end. Add `cannotDeleteAnchorSlot` and `slotCannotBeSplit` update errors and map them to clear UI messages.

- [ ] **Step 4: Run the focused tests and verify they pass**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:JonesControlTests/HeatingScheduleTests`

Expected: PASS.

- [ ] **Step 5: Commit**

~~~bash
git add JonesControl/Heating/HeatingSchedule.swift JonesControlTests/HeatingScheduleTests.swift
git commit -m "Add heating schedule slot operations"
~~~

### Task 3: Expose add and delete in SwiftUI

**Files:**

- Modify: `JonesControl/Heating/HeatingView.swift`
- Modify: `JonesControl/Heating/HeatingSlotEditorView.swift`
- Modify: `JonesControlTests/HeatingFeatureModelTests.swift`

**Interfaces:**

- Consumes: `addingOffSlot(after:)` and `deletingSlot(at:)`.
- Produces: an editor `Add slot after` action and a destructive editor `Delete slot` action.

- [ ] **Step 1: Write failing feature-model save coverage**

Construct a five-period `HeatingSchedule`, save it through `HeatingFeatureModel`, and assert the mock service receives the complete five-period document and replaces the revision from its response.

- [ ] **Step 2: Run the focused feature-model test and verify it fails**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:JonesControlTests/HeatingFeatureModelTests`

Expected: construction or mapping fails until Task 1 is complete.

- [ ] **Step 3: Add the controls**

In `HeatingSlotEditorView`, add an `Add slot after` button that saves the result of splitting the edited range through `model.save(schedule:)`, then dismisses. Add a confirmation-gated destructive `Delete slot` button for indexes above zero; it saves the transformed schedule then dismisses. Show neither action when its model operation is invalid. No new Schedule-list control is required in `HeatingView`.

- [ ] **Step 4: Run the focused feature-model tests and verify they pass**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:JonesControlTests/HeatingFeatureModelTests`

Expected: PASS.

- [ ] **Step 5: Commit**

~~~bash
git add JonesControl/Heating/HeatingSlotEditorView.swift JonesControlTests/HeatingFeatureModelTests.swift
git commit -m "Add variable heating slot controls"
~~~

### Task 4: Run regression verification

**Files:**

- Modify: `JonesControlTests/HeatingScheduleTests.swift` only if a regression test needs correction.

- [ ] **Step 1: Run the complete test suite**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`

Expected: PASS with no test failures.

- [ ] **Step 2: Inspect the final diff**

Run: `git diff HEAD~3..HEAD --check && git status --short`

Expected: no whitespace errors and no uncommitted feature files.

- [ ] **Step 3: Commit any final test correction**

~~~bash
git add JonesControlTests/HeatingScheduleTests.swift
git commit -m "Test variable heating schedule workflow"
~~~
