# Heating Schedule App Mapping

This document describes the app-local heating schedule shape used by `JonesControl` and how it maps toward the external heating API contract.

The main API contract is being documented separately in the main repo. This file is intentionally narrower: it explains the app-side model another Codex would need to consume when wiring `JonesControl` into `xtura-automation`.

## Local App Model

The Heating tab uses a local `HeatingSchedule` with exactly four visible slots.

Relevant types live in:

- `/Users/rog/.codex/worktrees/b3bf/JonesControl/JonesControl/Heating/HeatingSchedule.swift`

Core types:

- `HeatingSchedule`
- `HeatingScheduleVisibleSlot`
- `HeatingScheduleSlot`
- `HeatingScheduleMode`
- `HeatingScheduleExportPeriod`

### Visible Slots

`HeatingSchedule.visibleSlots` is always an array of length `4`.

The current intended shape is four explicit visible slots, each carrying a real schedule segment. User-facing UI should not expose an `empty` option.

`HeatingScheduleSlot` contains:

- `startMinuteOfDay`
- `endMinuteOfDay`
- `mode`
- `targetTemperatureCelsius`

Rules:

- `mode == .heat` requires `targetTemperatureCelsius`
- `mode == .off` canonicalizes `targetTemperatureCelsius` to `nil`
- `endMinuteOfDay` must be later than `startMinuteOfDay`
- every slot has a minimum duration of 15 minutes
- visible slots are contiguous in time order
- visible slots do not overlap
- slot `n`’s end boundary is the next slot’s start boundary

In practice, the visible schedule behaves like a linked chain.

## Update Path

Simple mode/target-only updates can still flow through:

- `HeatingSchedule.updatingVisibleSlot(at:with:)`

Boundary-aware editor writes should use:

- `HeatingSchedule.updatingLinkedSlot(at:startMinuteOfDay:endMinuteOfDay:mode:targetTemperatureCelsius:)`

Supporting helpers currently include:

- `HeatingSchedule.updatingSlotStart(at:to:)`
- `HeatingSchedule.updatingSlotEnd(at:to:)`
- `HeatingSchedule.editingBounds(forSlotAt:)`

These helpers preserve the linked chain:

- editing one slot start updates the previous slot end
- editing one slot end updates the next slot start
- if a boundary move would shrink later or earlier slots below 15 minutes, the change propagates through the chain

Current failure cases:

- `slotIndexOutOfRange`
- `slotCountInvalid`
- `validationErrors([HeatingScheduleValidationError])`

## Export Shape

For backend-oriented use, the app derives:

- `[HeatingScheduleExportPeriod]`

via:

- `HeatingSchedule.exportedPeriods()`

Each export period contains:

- `startMinuteOfDay`
- `mode`
- `targetTemperatureCelsius`

Important: export periods are start-based, not start/end pairs. The effective end of one period is the next period’s `startMinuteOfDay`.

## Hidden Off Period Derivation

The app does not store leading/trailing hidden periods directly in the visible UI.

Instead, `exportedPeriods()` derives them automatically by evaluating the effective state across the day boundary set:

- `0`
- `1440`
- every visible slot start
- every visible slot end

That means export can synthesize:

- a leading off period from `00:00` to the first visible slot
- a trailing off period from the last visible slot to `24:00`

Because the visible chain is contiguous, there should not be any visible-slot gaps in normal app state.

## Mapping Toward xtura-automation

The nearby backend project expects a day program that:

- starts at `00:00`
- uses ordered start-based periods
- uses `off` or `heat`
- includes target temperature only for `heat`

That aligns closely with `HeatingScheduleExportPeriod`.

The main mapping another Codex would need is:

1. Convert `startMinuteOfDay` into the backend local-time shape.
2. Map app mode:
   - `.off` -> backend `off`
   - `.heat` -> backend `heat`
3. Pass `targetTemperatureCelsius` only for heat periods.
4. Preserve export order exactly.

## Example

Visible schedule:

- slot 1: `06:30-08:00 heat 21C`
- slot 2: `08:00-12:00 off`
- slot 3: `12:00-18:00 heat 19C`
- slot 4: `18:00-22:00 off`

Export:

```text
00:00 off
06:30 heat 21
08:00 off
12:00 heat 19
18:00 off
22:00 off
```

## Integration Notes

- The current Heating tab is local-only. There is no persistence or network sync yet.
- UI formatting helpers live in `HeatingView` and `HeatingSlotEditorView`; do not scrape display strings for integration.
- For integration, use `HeatingSchedule` plus `exportedPeriods()`, not the rendered row text.
