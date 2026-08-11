# Variable heating slots

## Scope

Change JonesControl's heating schedule editor to support any valid number of
periods in its one enabled, all-days heating program. Do not change the
xtura-automation service or website, and do not add support for multiple
programs or weekday-specific programs in this work.

## Server contract

The service schedule document is retained as the source of truth. Its program
contains an ordered list of periods, whose first item starts at `00:00`; each
period lasts until the next period starts and the final period ends at
midnight. The client continues to send the complete document and last-read
revision on save.

JonesControl will load and save every period in the selected program, including
consecutive periods with the same effective state. It must neither pad nor
split a schedule merely to satisfy a client-side display count, and it must not
merge equivalent adjacent periods while saving.

## Schedule model

`HeatingSchedule` will store a variable-length ordered collection of contiguous
full-day ranges. The first range begins at minute zero and the final range ends
at minute 1440. The existing 15-minute minimum duration remains in effect.

The midnight-starting range is an anchor required by the API. It is shown in
the schedule list so the start-of-day state remains clear, but it cannot be
deleted. A schedule always retains at least that one range.

Editing a range continues to propagate shared boundaries to adjacent ranges,
subject to the minimum-duration constraint. Import validates ordering and heat
targets; export maps each stored range directly to one server period.

## User interface

The Schedule section lists all loaded ranges, with no fixed limit. Each range
editor includes an `Add slot after` control.

Adding a slot operates on the range being edited: it splits that range at a valid
15-minute-aligned midpoint and adds a second range. The newly created range is
initially Off; the retained first range preserves its prior state. If a range
cannot be split into two minimum-duration ranges, the control is unavailable.

Each range editor offers a destructive `Delete slot` action. Deleting a
non-anchor range removes its starting transition and extends the preceding
range through the deleted range. The anchor range has no delete action. After
any structural or field edit, the existing explicit Save flow submits the full
schedule and refreshes from the service response.

## Error handling

Invalid local time edits and unsplittable additions are prevented or reported
using the existing editor error presentation. Server validation and revision
conflicts keep their current behaviour: validation feedback is displayed, and
a conflict reloads the server schedule.

## Tests

Add coverage for:

- importing and exporting a five-period schedule without changes;
- preserving consecutive equivalent periods;
- splitting a range into an Off new slot;
- refusing a split when it violates the 15-minute duration;
- deleting a non-anchor range and joining its neighbouring ranges;
- refusing deletion of the midnight anchor; and
- saving a variable-length schedule with the returned revision.
