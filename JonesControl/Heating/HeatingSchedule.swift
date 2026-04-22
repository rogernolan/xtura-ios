import Foundation

struct HeatingSchedule: Equatable, Sendable {
    static let visibleSlotCount = 4
    static let minimumSlotDurationMinutes = 15
    static let minutesInDay = 24 * 60

    var visibleSlots: [HeatingScheduleVisibleSlot]

    init?(visibleSlots: [HeatingScheduleVisibleSlot]) {
        guard visibleSlots.count == Self.visibleSlotCount else {
            return nil
        }

        var canonicalizedSlots: [HeatingScheduleVisibleSlot] = []
        canonicalizedSlots.reserveCapacity(visibleSlots.count)

        for visibleSlot in visibleSlots {
            guard case .active(let slot) = visibleSlot else {
                return nil
            }

            canonicalizedSlots.append(.active(slot.canonicalized))
        }

        self.visibleSlots = canonicalizedSlots
    }

    init?(activeSlots: [HeatingScheduleSlot]) {
        guard activeSlots.count == Self.visibleSlotCount else {
            return nil
        }

        self.init(visibleSlots: activeSlots.map(HeatingScheduleVisibleSlot.active))
    }

    func updatingVisibleSlot(
        at index: Int,
        with visibleSlot: HeatingScheduleVisibleSlot
    ) -> Result<HeatingSchedule, HeatingScheduleUpdateError> {
        guard visibleSlots.indices.contains(index) else {
            return .failure(.slotIndexOutOfRange)
        }

        guard case .active(let slot) = visibleSlot else {
            return .failure(.slotCountInvalid)
        }

        var updatedVisibleSlots = visibleSlots
        updatedVisibleSlots[index] = .active(Self.canonicalize(slot))

        return Self.makeValidatedSchedule(from: updatedVisibleSlots)
    }

    func editingBounds(forSlotAt index: Int) -> HeatingScheduleSlotEditingBounds? {
        guard visibleSlots.indices.contains(index) else {
            return nil
        }

        let slots = activeSlots
        let earliestStartMinuteOfDay = slots[0].startMinuteOfDay + (index * Self.minimumSlotDurationMinutes)
        let latestEndMinuteOfDay = slots[slots.index(before: slots.endIndex)].endMinuteOfDay
            - ((slots.count - index - 1) * Self.minimumSlotDurationMinutes)

        guard latestEndMinuteOfDay - earliestStartMinuteOfDay >= Self.minimumSlotDurationMinutes else {
            return nil
        }

        return HeatingScheduleSlotEditingBounds(
            earliestStartMinuteOfDay: earliestStartMinuteOfDay,
            latestStartMinuteOfDay: latestEndMinuteOfDay - Self.minimumSlotDurationMinutes,
            earliestEndMinuteOfDay: earliestStartMinuteOfDay + Self.minimumSlotDurationMinutes,
            latestEndMinuteOfDay: latestEndMinuteOfDay
        )
    }

    func updatingLinkedSlot(
        at index: Int,
        startMinuteOfDay: Int,
        endMinuteOfDay: Int,
        mode: HeatingScheduleMode,
        targetTemperatureCelsius: Double?
    ) -> Result<HeatingSchedule, HeatingScheduleUpdateError> {
        guard visibleSlots.indices.contains(index) else {
            return .failure(.slotIndexOutOfRange)
        }

        var updatedSchedule = self
        let currentSlot = activeSlots[index]

        if startMinuteOfDay != currentSlot.startMinuteOfDay {
            switch updatedSchedule.updatingSlotStart(at: index, to: startMinuteOfDay) {
            case .success(let schedule):
                updatedSchedule = schedule
            case .failure(let error):
                return .failure(error)
            }
        }

        if endMinuteOfDay != updatedSchedule.activeSlots[index].endMinuteOfDay {
            switch updatedSchedule.updatingSlotEnd(at: index, to: endMinuteOfDay) {
            case .success(let schedule):
                updatedSchedule = schedule
            case .failure(let error):
                return .failure(error)
            }
        }

        var slots = updatedSchedule.activeSlots
        let updatedSlot = slots[index]
        slots[index] = HeatingScheduleSlot(
            startMinuteOfDay: updatedSlot.startMinuteOfDay,
            endMinuteOfDay: updatedSlot.endMinuteOfDay,
            mode: mode,
            targetTemperatureCelsius: targetTemperatureCelsius
        )

        return Self.makeValidatedSchedule(from: slots.map(HeatingScheduleVisibleSlot.active))
    }

    func updatingSlotEnd(
        at index: Int,
        to endMinuteOfDay: Int
    ) -> Result<HeatingSchedule, HeatingScheduleUpdateError> {
        guard visibleSlots.indices.contains(index) else {
            return .failure(.slotIndexOutOfRange)
        }

        var slots = activeSlots
        guard let bounds = editingBounds(forSlotAt: index) else {
            return .failure(.slotCountInvalid)
        }

        let updatedSlot = slots[index]
        guard endMinuteOfDay >= updatedSlot.startMinuteOfDay + Self.minimumSlotDurationMinutes,
              endMinuteOfDay <= bounds.latestEndMinuteOfDay else {
            return .failure(.validationErrors([.invalidTimeRange(slotIndex: index)]))
        }

        slots[index] = HeatingScheduleSlot(
            startMinuteOfDay: updatedSlot.startMinuteOfDay,
            endMinuteOfDay: endMinuteOfDay,
            mode: updatedSlot.mode,
            targetTemperatureCelsius: updatedSlot.targetTemperatureCelsius
        )

        guard slots[index].endMinuteOfDay - slots[index].startMinuteOfDay >= Self.minimumSlotDurationMinutes else {
            return .failure(.validationErrors([.invalidTimeRange(slotIndex: index)]))
        }

        if index < slots.index(before: slots.endIndex) {
            slots[index + 1] = Self.slotWithUpdatedStart(slots[index + 1], startMinuteOfDay: endMinuteOfDay)

            for propagatedIndex in (index + 1)..<slots.count {
                let minimumEnd = slots[propagatedIndex].startMinuteOfDay + Self.minimumSlotDurationMinutes
                if slots[propagatedIndex].endMinuteOfDay >= minimumEnd {
                    continue
                }

                slots[propagatedIndex] = Self.slotWithUpdatedEnd(slots[propagatedIndex], endMinuteOfDay: minimumEnd)
                if propagatedIndex < slots.index(before: slots.endIndex) {
                    slots[propagatedIndex + 1] = Self.slotWithUpdatedStart(
                        slots[propagatedIndex + 1],
                        startMinuteOfDay: minimumEnd
                    )
                }
            }
        }

        return Self.makeValidatedSchedule(from: slots.map(HeatingScheduleVisibleSlot.active))
    }

    func updatingSlotStart(
        at index: Int,
        to startMinuteOfDay: Int
    ) -> Result<HeatingSchedule, HeatingScheduleUpdateError> {
        guard visibleSlots.indices.contains(index) else {
            return .failure(.slotIndexOutOfRange)
        }

        var slots = activeSlots
        guard let bounds = editingBounds(forSlotAt: index) else {
            return .failure(.slotCountInvalid)
        }

        let updatedSlot = slots[index]
        guard startMinuteOfDay >= bounds.earliestStartMinuteOfDay,
              startMinuteOfDay <= updatedSlot.endMinuteOfDay - Self.minimumSlotDurationMinutes else {
            return .failure(.validationErrors([.invalidTimeRange(slotIndex: index)]))
        }

        slots[index] = HeatingScheduleSlot(
            startMinuteOfDay: startMinuteOfDay,
            endMinuteOfDay: updatedSlot.endMinuteOfDay,
            mode: updatedSlot.mode,
            targetTemperatureCelsius: updatedSlot.targetTemperatureCelsius
        )

        guard slots[index].endMinuteOfDay - slots[index].startMinuteOfDay >= Self.minimumSlotDurationMinutes else {
            return .failure(.validationErrors([.invalidTimeRange(slotIndex: index)]))
        }

        if index > 0 {
            slots[index - 1] = Self.slotWithUpdatedEnd(slots[index - 1], endMinuteOfDay: startMinuteOfDay)

            for propagatedIndex in stride(from: index - 1, through: 0, by: -1) {
                let minimumStart = slots[propagatedIndex].endMinuteOfDay - Self.minimumSlotDurationMinutes
                if slots[propagatedIndex].startMinuteOfDay <= minimumStart {
                    continue
                }

                slots[propagatedIndex] = Self.slotWithUpdatedStart(
                    slots[propagatedIndex],
                    startMinuteOfDay: minimumStart
                )
                if propagatedIndex > 0 {
                    slots[propagatedIndex - 1] = Self.slotWithUpdatedEnd(
                        slots[propagatedIndex - 1],
                        endMinuteOfDay: minimumStart
                    )
                }
            }
        }

        return Self.makeValidatedSchedule(from: slots.map(HeatingScheduleVisibleSlot.active))
    }

    private static func makeValidatedSchedule(
        from visibleSlots: [HeatingScheduleVisibleSlot]
    ) -> Result<HeatingSchedule, HeatingScheduleUpdateError> {
        guard let updatedSchedule = HeatingSchedule(visibleSlots: visibleSlots) else {
            return .failure(.slotCountInvalid)
        }

        let errors = updatedSchedule.validationErrors
        guard errors.isEmpty else {
            return .failure(.validationErrors(errors))
        }

        return .success(updatedSchedule)
    }

    nonisolated private static func canonicalize(_ slot: HeatingScheduleSlot) -> HeatingScheduleSlot {
        slot.canonicalized
    }

    private static func slotWithUpdatedStart(
        _ slot: HeatingScheduleSlot,
        startMinuteOfDay: Int
    ) -> HeatingScheduleSlot {
        HeatingScheduleSlot(
            startMinuteOfDay: startMinuteOfDay,
            endMinuteOfDay: slot.endMinuteOfDay,
            mode: slot.mode,
            targetTemperatureCelsius: slot.targetTemperatureCelsius
        )
    }

    private static func slotWithUpdatedEnd(
        _ slot: HeatingScheduleSlot,
        endMinuteOfDay: Int
    ) -> HeatingScheduleSlot {
        HeatingScheduleSlot(
            startMinuteOfDay: slot.startMinuteOfDay,
            endMinuteOfDay: endMinuteOfDay,
            mode: slot.mode,
            targetTemperatureCelsius: slot.targetTemperatureCelsius
        )
    }

    var activeSlots: [HeatingScheduleSlot] {
        visibleSlots.map { visibleSlot in
            guard case .active(let slot) = visibleSlot else {
                preconditionFailure("HeatingSchedule stores only explicit visible slots.")
            }

            return slot
        }
    }

    var validationErrors: [HeatingScheduleValidationError] {
        let activeEntries = activeSlots.enumerated().map { (index: $0.offset, slot: $0.element) }

        var errors: [HeatingScheduleValidationError] = []
        for entry in activeEntries {
            let slot = entry.slot

            if slot.startMinuteOfDay < 0 || slot.startMinuteOfDay >= Self.minutesInDay {
                errors.append(.startMinuteOutOfRange(slotIndex: entry.index, minute: slot.startMinuteOfDay))
            }

            if slot.endMinuteOfDay < 0 || slot.endMinuteOfDay > Self.minutesInDay {
                errors.append(.endMinuteOutOfRange(slotIndex: entry.index, minute: slot.endMinuteOfDay))
            }

            if slot.endMinuteOfDay <= slot.startMinuteOfDay {
                errors.append(.invalidTimeRange(slotIndex: entry.index))
            }

            let durationMinutes = slot.endMinuteOfDay - slot.startMinuteOfDay
            if durationMinutes > 0 && durationMinutes < Self.minimumSlotDurationMinutes {
                errors.append(.invalidTimeRange(slotIndex: entry.index))
            }

            switch slot.mode {
            case .heat:
                if slot.targetTemperatureCelsius == nil {
                    errors.append(.missingTargetTemperature(slotIndex: entry.index))
                }
            case .off:
                break
            }
        }

        for pair in zip(activeEntries, activeEntries.dropFirst()) {
            let previous = pair.0
            let next = pair.1

            guard previous.slot.endMinuteOfDay > previous.slot.startMinuteOfDay,
                  next.slot.endMinuteOfDay > next.slot.startMinuteOfDay else {
                continue
            }

            if previous.slot.endMinuteOfDay > next.slot.startMinuteOfDay {
                errors.append(.overlappingSlots(previousSlotIndex: previous.index, nextSlotIndex: next.index))
            } else if previous.slot.endMinuteOfDay < next.slot.startMinuteOfDay {
                errors.append(.overlappingSlots(previousSlotIndex: previous.index, nextSlotIndex: next.index))
            }
        }

        return errors
    }

    func exportedPeriods() throws -> [HeatingScheduleExportPeriod] {
        let errors = validationErrors
        guard errors.isEmpty else {
            throw HeatingScheduleExportValidationError(errors: errors)
        }

        let slots = activeSlots.sorted { lhs, rhs in
            if lhs.startMinuteOfDay == rhs.startMinuteOfDay {
                return lhs.endMinuteOfDay < rhs.endMinuteOfDay
            }

            return lhs.startMinuteOfDay < rhs.startMinuteOfDay
        }

        return Self.makeExportPeriods(from: slots)
    }

    private static func makeExportPeriods(from slots: [HeatingScheduleSlot]) -> [HeatingScheduleExportPeriod] {
        let boundaries = Array(
            Set(
                [0, Self.minutesInDay]
                + slots.flatMap { [$0.startMinuteOfDay, $0.endMinuteOfDay] }
            )
        )
        .sorted()

        var periods: [HeatingScheduleExportPeriod] = []
        var lastState: HeatingScheduleExportState?

        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            guard end > start else {
                continue
            }

            let midpoint = start + ((end - start) / 2)
            let state = Self.state(at: midpoint, in: slots)

            if state != lastState {
                periods.append(
                    HeatingScheduleExportPeriod(
                        startMinuteOfDay: start,
                        mode: state.mode,
                        targetTemperatureCelsius: state.targetTemperatureCelsius
                    )
                )
                lastState = state
            }
        }

        if periods.isEmpty {
            periods.append(
                HeatingScheduleExportPeriod(
                    startMinuteOfDay: 0,
                    mode: .off,
                    targetTemperatureCelsius: nil
                )
            )
        }

        return periods
    }

    private static func state(at minuteOfDay: Int, in slots: [HeatingScheduleSlot]) -> HeatingScheduleExportState {
        guard let slot = slots.first(where: { $0.startMinuteOfDay <= minuteOfDay && minuteOfDay < $0.endMinuteOfDay }) else {
            return .off
        }

        return slot.effectiveState
    }
}

struct HeatingScheduleSlot: Equatable, Sendable {
    let startMinuteOfDay: Int
    let endMinuteOfDay: Int
    let mode: HeatingScheduleMode
    let targetTemperatureCelsius: Double?

    nonisolated init(
        startMinuteOfDay: Int,
        endMinuteOfDay: Int,
        mode: HeatingScheduleMode,
        targetTemperatureCelsius: Double? = nil
    ) {
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.mode = mode
        switch mode {
        case .off:
            self.targetTemperatureCelsius = nil
        case .heat:
            self.targetTemperatureCelsius = targetTemperatureCelsius
        }
    }

    nonisolated fileprivate var canonicalized: HeatingScheduleSlot {
        HeatingScheduleSlot(
            startMinuteOfDay: startMinuteOfDay,
            endMinuteOfDay: endMinuteOfDay,
            mode: mode,
            targetTemperatureCelsius: targetTemperatureCelsius
        )
    }

    fileprivate var effectiveState: HeatingScheduleExportState {
        switch mode {
        case .off:
            return .off
        case .heat:
            return HeatingScheduleExportState(mode: .heat, targetTemperatureCelsius: targetTemperatureCelsius)
        }
    }
}

enum HeatingScheduleMode: Equatable, Sendable {
    case off
    case heat
}

enum HeatingScheduleVisibleSlot: Equatable, Sendable {
    case empty
    case active(HeatingScheduleSlot)
}

struct HeatingScheduleSlotEditingBounds: Equatable, Sendable {
    let earliestStartMinuteOfDay: Int
    let latestStartMinuteOfDay: Int
    let earliestEndMinuteOfDay: Int
    let latestEndMinuteOfDay: Int
}

struct HeatingScheduleExportPeriod: Equatable, Sendable {
    var startMinuteOfDay: Int
    var mode: HeatingScheduleMode
    var targetTemperatureCelsius: Double?

    init(startMinuteOfDay: Int, mode: HeatingScheduleMode, targetTemperatureCelsius: Double? = nil) {
        self.startMinuteOfDay = startMinuteOfDay
        self.mode = mode
        self.targetTemperatureCelsius = targetTemperatureCelsius
    }
}

enum HeatingScheduleValidationError: Error, Equatable, Sendable {
    case startMinuteOutOfRange(slotIndex: Int, minute: Int)
    case endMinuteOutOfRange(slotIndex: Int, minute: Int)
    case invalidTimeRange(slotIndex: Int)
    case missingTargetTemperature(slotIndex: Int)
    case overlappingSlots(previousSlotIndex: Int, nextSlotIndex: Int)
}

enum HeatingScheduleUpdateError: Error, Equatable, Sendable {
    case slotIndexOutOfRange
    case slotCountInvalid
    case validationErrors([HeatingScheduleValidationError])
}

struct HeatingScheduleExportValidationError: Error, Equatable, Sendable {
    var errors: [HeatingScheduleValidationError]
}

private struct HeatingScheduleExportState: Equatable, Sendable {
    var mode: HeatingScheduleMode
    var targetTemperatureCelsius: Double?

    static let off = HeatingScheduleExportState(mode: .off, targetTemperatureCelsius: nil)
}
