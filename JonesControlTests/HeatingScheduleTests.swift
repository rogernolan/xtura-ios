import Testing
@testable import JonesControl

struct HeatingScheduleTests {
    @Test func offSlotsAreCanonicalizedWithoutATargetTemperature() {
        let offSlot = HeatingScheduleSlot(
            startMinuteOfDay: 0,
            endMinuteOfDay: 60,
            mode: .off,
            targetTemperatureCelsius: 18
        )

        #expect(offSlot.targetTemperatureCelsius == nil)
    }

    @Test func schedulesAcceptAnyPositiveNumberOfExplicitSlots() {
        let baseSlots = makeLinkedSlots()
        let visibleSlots = baseSlots.map(HeatingScheduleVisibleSlot.active)
        let placeholderSlots: [HeatingScheduleVisibleSlot] = [
            .active(baseSlots[0]),
            .active(baseSlots[1]),
            .empty,
            .active(baseSlots[3])
        ]
        #expect(HeatingSchedule(visibleSlots: []) == nil)
        #expect(HeatingSchedule(visibleSlots: placeholderSlots) == nil)
        #expect(HeatingSchedule(activeSlots: Array(baseSlots.prefix(3))) != nil)
        #expect(HeatingSchedule(visibleSlots: visibleSlots) != nil)
    }

    @Test func updatingVisibleSlotReturnsANewScheduleForValidModeEdits() {
        let schedule = makeSchedule()
        let updatedSlot = HeatingScheduleSlot(
            startMinuteOfDay: 9 * 60,
            endMinuteOfDay: 10 * 60,
            mode: .heat,
            targetTemperatureCelsius: 22
        )

        switch schedule.updatingVisibleSlot(at: 1, with: .active(updatedSlot)) {
        case .success(let updatedSchedule):
            #expect(updatedSchedule.visibleSlots[1] == .active(updatedSlot))
            #expect(updatedSchedule.visibleSlots[0] == schedule.visibleSlots[0])
            #expect(updatedSchedule.visibleSlots[2] == schedule.visibleSlots[2])
        case .failure(let error):
            Issue.record("Expected update to succeed, got \(error).")
        }
    }

    @Test func updatingVisibleSlotRejectsEmptyPlaceholders() {
        let schedule = makeSchedule()

        switch schedule.updatingVisibleSlot(at: 1, with: .empty) {
        case .success:
            Issue.record("Expected update to fail.")
        case .failure(.slotCountInvalid):
            break
        case .failure(let error):
            Issue.record("Expected slot-count failure, got \(error).")
        }
    }

    @Test func updatingVisibleSlotRejectsMissingTargetsForHeatSlots() {
        let schedule = makeSchedule()
        let invalidSlot = HeatingScheduleSlot(
            startMinuteOfDay: 8 * 60,
            endMinuteOfDay: 9 * 60,
            mode: .heat
        )

        switch schedule.updatingVisibleSlot(at: 0, with: .active(invalidSlot)) {
        case .success:
            Issue.record("Expected update to fail.")
        case .failure(.validationErrors(let errors)):
            #expect(errors == [.missingTargetTemperature(slotIndex: 0)])
        case .failure(let error):
            Issue.record("Expected validation error, got \(error).")
        }
    }

    @Test func addingOffSlotSplitsTheSelectedRangeAtItsMidpoint() {
        let schedule = HeatingSchedule(activeSlots: [
            HeatingScheduleSlot(startMinuteOfDay: 0, endMinuteOfDay: 6 * 60, mode: .off),
            HeatingScheduleSlot(startMinuteOfDay: 6 * 60, endMinuteOfDay: 8 * 60, mode: .heat, targetTemperatureCelsius: 20),
            HeatingScheduleSlot(startMinuteOfDay: 8 * 60, endMinuteOfDay: HeatingSchedule.minutesInDay, mode: .off)
        ])!

        switch schedule.addingOffSlot(after: 1) {
        case .success(let updated):
            #expect(updated.activeSlots[1] == HeatingScheduleSlot(
                startMinuteOfDay: 6 * 60,
                endMinuteOfDay: 7 * 60,
                mode: .heat,
                targetTemperatureCelsius: 20
            ))
            #expect(updated.activeSlots[2] == HeatingScheduleSlot(
                startMinuteOfDay: 7 * 60,
                endMinuteOfDay: 8 * 60,
                mode: .off
            ))
        case .failure(let error):
            Issue.record("Expected split to succeed, got \(error).")
        }
    }

    @Test func addingOffSlotRejectsAMinimumDurationRange() {
        let schedule = HeatingSchedule(activeSlots: [
            HeatingScheduleSlot(startMinuteOfDay: 0, endMinuteOfDay: 15, mode: .off),
            HeatingScheduleSlot(startMinuteOfDay: 15, endMinuteOfDay: HeatingSchedule.minutesInDay, mode: .off)
        ])!

        #expect(schedule.addingOffSlot(after: 0) == .failure(.slotCannotBeSplit))
    }

    @Test func deletingSlotExtendsThePrecedingRange() {
        let schedule = HeatingSchedule(activeSlots: [
            HeatingScheduleSlot(startMinuteOfDay: 0, endMinuteOfDay: 6 * 60, mode: .off),
            HeatingScheduleSlot(startMinuteOfDay: 6 * 60, endMinuteOfDay: 8 * 60, mode: .heat, targetTemperatureCelsius: 20),
            HeatingScheduleSlot(startMinuteOfDay: 8 * 60, endMinuteOfDay: HeatingSchedule.minutesInDay, mode: .off)
        ])!

        switch schedule.deletingSlot(at: 1) {
        case .success(let updated):
            #expect(updated.activeSlots == [
                HeatingScheduleSlot(startMinuteOfDay: 0, endMinuteOfDay: 8 * 60, mode: .off),
                HeatingScheduleSlot(startMinuteOfDay: 8 * 60, endMinuteOfDay: HeatingSchedule.minutesInDay, mode: .off)
            ])
        case .failure(let error):
            Issue.record("Expected deletion to succeed, got \(error).")
        }
    }

    @Test func deletingSlotRejectsTheMidnightAnchor() {
        let schedule = makeSchedule()

        #expect(schedule.deletingSlot(at: 0) == .failure(.cannotDeleteAnchorSlot))
    }

    @Test func editingBoundsReserveMinimumTimeForTheRemainingChain() {
        let schedule = makeSchedule()

        #expect(schedule.editingBounds(forSlotAt: 0) == HeatingScheduleSlotEditingBounds(
            earliestStartMinuteOfDay: 8 * 60,
            latestStartMinuteOfDay: 11 * 60,
            earliestEndMinuteOfDay: 8 * 60 + 15,
            latestEndMinuteOfDay: 11 * 60 + 15
        ))
        #expect(schedule.editingBounds(forSlotAt: 2) == HeatingScheduleSlotEditingBounds(
            earliestStartMinuteOfDay: 8 * 60 + 30,
            latestStartMinuteOfDay: 11 * 60 + 30,
            earliestEndMinuteOfDay: 8 * 60 + 45,
            latestEndMinuteOfDay: 11 * 60 + 45
        ))
    }

    @Test func updatingSlotEndPropagatesForwardFromEditedBoundary() {
        let schedule = makeSchedule()

        switch schedule.updatingSlotEnd(at: 0, to: 9 * 60 + 15) {
        case .success(let updatedSchedule):
            #expect(updatedSchedule.activeSlots[0] == HeatingScheduleSlot(
                startMinuteOfDay: 8 * 60,
                endMinuteOfDay: 9 * 60 + 15,
                mode: .heat,
                targetTemperatureCelsius: 21
            ))
            #expect(updatedSchedule.activeSlots[1] == HeatingScheduleSlot(
                startMinuteOfDay: 9 * 60 + 15,
                endMinuteOfDay: 10 * 60,
                mode: .off
            ))
            #expect(updatedSchedule.activeSlots[2] == schedule.activeSlots[2])
            #expect(updatedSchedule.activeSlots[3] == schedule.activeSlots[3])
        case .failure(let error):
            Issue.record("Expected propagated end update to succeed, got \(error).")
        }
    }

    @Test func updatingLinkedSlotAppliesModeChangesAndBoundaryPropagationTogether() {
        let schedule = makeSchedule()

        switch schedule.updatingLinkedSlot(
            at: 1,
            startMinuteOfDay: 9 * 60 + 15,
            endMinuteOfDay: 10 * 60 + 30,
            mode: .heat,
            targetTemperatureCelsius: 22
        ) {
        case .success(let updatedSchedule):
            #expect(updatedSchedule.activeSlots == [
                HeatingScheduleSlot(
                    startMinuteOfDay: 8 * 60,
                    endMinuteOfDay: 9 * 60 + 15,
                    mode: .heat,
                    targetTemperatureCelsius: 21
                ),
                HeatingScheduleSlot(
                    startMinuteOfDay: 9 * 60 + 15,
                    endMinuteOfDay: 10 * 60 + 30,
                    mode: .heat,
                    targetTemperatureCelsius: 22
                ),
                HeatingScheduleSlot(
                    startMinuteOfDay: 10 * 60 + 30,
                    endMinuteOfDay: 11 * 60,
                    mode: .heat,
                    targetTemperatureCelsius: 20
                ),
                HeatingScheduleSlot(
                    startMinuteOfDay: 11 * 60,
                    endMinuteOfDay: 12 * 60,
                    mode: .off
                )
            ])
        case .failure(let error):
            Issue.record("Expected linked update to succeed, got \(error).")
        }
    }

    @Test func updatingSlotStartPropagatesBackwardFromEditedBoundary() {
        let schedule = makeSchedule()

        switch schedule.updatingSlotStart(at: 2, to: 9 * 60 + 45) {
        case .success(let updatedSchedule):
            #expect(updatedSchedule.activeSlots[1] == HeatingScheduleSlot(
                startMinuteOfDay: 9 * 60,
                endMinuteOfDay: 9 * 60 + 45,
                mode: .off
            ))
            #expect(updatedSchedule.activeSlots[2] == HeatingScheduleSlot(
                startMinuteOfDay: 9 * 60 + 45,
                endMinuteOfDay: 11 * 60,
                mode: .heat,
                targetTemperatureCelsius: 20
            ))
            #expect(updatedSchedule.activeSlots[0] == schedule.activeSlots[0])
            #expect(updatedSchedule.activeSlots[3] == schedule.activeSlots[3])
        case .failure(let error):
            Issue.record("Expected propagated start update to succeed, got \(error).")
        }
    }

    @Test func largeEndEditsCompressLaterSlotsWithoutExtendingTheVisibleChain() {
        let schedule = makeSchedule()

        switch schedule.updatingSlotEnd(at: 0, to: 11 * 60 + 15) {
        case .success(let updatedSchedule):
            #expect(updatedSchedule.activeSlots == [
                HeatingScheduleSlot(
                    startMinuteOfDay: 8 * 60,
                    endMinuteOfDay: 11 * 60 + 15,
                    mode: .heat,
                    targetTemperatureCelsius: 21
                ),
                HeatingScheduleSlot(
                    startMinuteOfDay: 11 * 60 + 15,
                    endMinuteOfDay: 11 * 60 + 30,
                    mode: .off
                ),
                HeatingScheduleSlot(
                    startMinuteOfDay: 11 * 60 + 30,
                    endMinuteOfDay: 11 * 60 + 45,
                    mode: .heat,
                    targetTemperatureCelsius: 20
                ),
                HeatingScheduleSlot(
                    startMinuteOfDay: 11 * 60 + 45,
                    endMinuteOfDay: 12 * 60,
                    mode: .off
                )
            ])
        case .failure(let error):
            Issue.record("Expected multi-slot propagation to succeed, got \(error).")
        }
    }

    @Test func largeEndEditsThatWouldOverflowTheVisibleChainAreRejected() {
        let schedule = makeSchedule()

        switch schedule.updatingSlotEnd(at: 0, to: 11 * 60 + 30) {
        case .success:
            Issue.record("Expected update to fail.")
        case .failure(.validationErrors(let errors)):
            #expect(errors == [.invalidTimeRange(slotIndex: 0)])
        case .failure(let error):
            Issue.record("Expected validation error, got \(error).")
        }
    }

    @Test func minimumDurationIsPreservedForBoundaryEdits() {
        let schedule = makeSchedule()

        switch schedule.updatingSlotEnd(at: 0, to: 8 * 60 + 10) {
        case .success:
            Issue.record("Expected update to fail.")
        case .failure(.validationErrors(let errors)):
            #expect(errors == [.invalidTimeRange(slotIndex: 0)])
        case .failure(let error):
            Issue.record("Expected validation error, got \(error).")
        }
    }

    @Test func validationReportsContiguityAndDurationProblems() {
        let invalidSlots: [HeatingScheduleVisibleSlot] = [
            .active(HeatingScheduleSlot(
                startMinuteOfDay: 8 * 60,
                endMinuteOfDay: 8 * 60 + 10,
                mode: .heat,
                targetTemperatureCelsius: 21
            )),
            .active(HeatingScheduleSlot(
                startMinuteOfDay: 8 * 60 + 30,
                endMinuteOfDay: 9 * 60,
                mode: .off
            )),
            .active(HeatingScheduleSlot(
                startMinuteOfDay: 9 * 60,
                endMinuteOfDay: 10 * 60,
                mode: .heat,
                targetTemperatureCelsius: 20
            )),
            .active(HeatingScheduleSlot(
                startMinuteOfDay: 10 * 60,
                endMinuteOfDay: 11 * 60,
                mode: .off
            ))
        ]

        guard let schedule = HeatingSchedule(visibleSlots: invalidSlots) else {
            Issue.record("Expected schedule construction to succeed.")
            return
        }

        #expect(schedule.validationErrors == [
            .invalidTimeRange(slotIndex: 0),
            .overlappingSlots(previousSlotIndex: 0, nextSlotIndex: 1)
        ])
    }

    @Test func exportDerivesOptionalLeadingAndTrailingOffPeriodsFromVisibleChain() throws {
        let visibleSlots: [HeatingScheduleSlot] = [
            HeatingScheduleSlot(
                startMinuteOfDay: 6 * 60,
                endMinuteOfDay: 8 * 60,
                mode: .heat,
                targetTemperatureCelsius: 21
            ),
            HeatingScheduleSlot(
                startMinuteOfDay: 8 * 60,
                endMinuteOfDay: 12 * 60,
                mode: .off
            ),
            HeatingScheduleSlot(
                startMinuteOfDay: 12 * 60,
                endMinuteOfDay: 17 * 60,
                mode: .heat,
                targetTemperatureCelsius: 20
            ),
            HeatingScheduleSlot(
                startMinuteOfDay: 17 * 60,
                endMinuteOfDay: 22 * 60,
                mode: .heat,
                targetTemperatureCelsius: 19
            )
        ]

        guard let schedule = HeatingSchedule(activeSlots: visibleSlots) else {
            Issue.record("Expected schedule construction to succeed.")
            return
        }

        #expect(try schedule.exportedPeriods() == [
            HeatingScheduleExportPeriod(startMinuteOfDay: 0, mode: .off),
            HeatingScheduleExportPeriod(startMinuteOfDay: 6 * 60, mode: .heat, targetTemperatureCelsius: 21),
            HeatingScheduleExportPeriod(startMinuteOfDay: 8 * 60, mode: .off),
            HeatingScheduleExportPeriod(startMinuteOfDay: 12 * 60, mode: .heat, targetTemperatureCelsius: 20),
            HeatingScheduleExportPeriod(startMinuteOfDay: 17 * 60, mode: .heat, targetTemperatureCelsius: 19),
            HeatingScheduleExportPeriod(startMinuteOfDay: 22 * 60, mode: .off)
        ])
    }

    @Test func rowDisplayFormatsTimeModeAndTargetTemperature() {
        let heatSlot = HeatingScheduleSlot(
            startMinuteOfDay: 6 * 60 + 30,
            endMinuteOfDay: 8 * 60,
            mode: .heat,
            targetTemperatureCelsius: 21
        )
        let offSlot = HeatingScheduleSlot(
            startMinuteOfDay: 8 * 60,
            endMinuteOfDay: 17 * 60,
            mode: .off
        )
        let heatDisplay = HeatingScheduleRowDisplay(slot: heatSlot)
        let offDisplay = HeatingScheduleRowDisplay(slot: offSlot)

        #expect(heatDisplay == HeatingScheduleRowDisplay(
            timeRangeText: "06:30 - 08:00",
            modeText: "On",
            targetTemperatureText: "21°C"
        ))
        #expect(offDisplay == HeatingScheduleRowDisplay(
            timeRangeText: "08:00 - 17:00",
            modeText: "Off",
            targetTemperatureText: nil
        ))
    }

    @Test func rowDisplayFormatsEndOfDayAs2400() {
        let finalSlot = HeatingScheduleSlot(
            startMinuteOfDay: 17 * 60,
            endMinuteOfDay: HeatingSchedule.minutesInDay,
            mode: .heat,
            targetTemperatureCelsius: 19
        )

        #expect(HeatingScheduleRowDisplay(slot: finalSlot) == HeatingScheduleRowDisplay(
            timeRangeText: "17:00 - 24:00",
            modeText: "On",
            targetTemperatureText: "19°C"
        ))
    }

    @Test func rowDisplayHandlesInvalidMinutesSafely() {
        let invalidSlot = HeatingScheduleSlot(
            startMinuteOfDay: -15,
            endMinuteOfDay: HeatingSchedule.minutesInDay + 1,
            mode: .heat,
            targetTemperatureCelsius: 18
        )
        let invalidDisplay = HeatingScheduleRowDisplay(slot: invalidSlot)

        #expect(invalidDisplay == HeatingScheduleRowDisplay(
            timeRangeText: "--:-- - --:--",
            modeText: "On",
            targetTemperatureText: "18°C"
        ))
    }

    @Test func linkedDocumentMappingImportsOneAllDaysProgramAndPreservesMetadata() throws {
        let document = HeatingScheduleDocument(
            timezone: "Europe/London",
            programs: [
                HeatingScheduleProgram(
                    id: "everyday-default",
                    enabled: true,
                    days: HeatingScheduleWeekday.allDays,
                    periods: [
                        HeatingSchedulePeriod(start: "00:00", mode: .off),
                        HeatingSchedulePeriod(start: "05:30", mode: .heat, targetCelsius: 20),
                        HeatingSchedulePeriod(start: "08:00", mode: .off)
                    ]
                )
            ],
            revision: "2026-04-22T09:31:45.123456Z"
        )

        let linkedDocument = try HeatingSchedule.linkedDocument(from: document)

        #expect(linkedDocument.timezone == "Europe/London")
        #expect(linkedDocument.revision == "2026-04-22T09:31:45.123456Z")
        #expect(linkedDocument.programID == "everyday-default")
        #expect(linkedDocument.schedule.activeSlots == [
            HeatingScheduleSlot(
                startMinuteOfDay: 0,
                endMinuteOfDay: 5 * 60 + 30,
                mode: .off
            ),
            HeatingScheduleSlot(
                startMinuteOfDay: 5 * 60 + 30,
                endMinuteOfDay: 8 * 60,
                mode: .heat,
                targetTemperatureCelsius: 20
            ),
            HeatingScheduleSlot(
                startMinuteOfDay: 8 * 60,
                endMinuteOfDay: 8 * 60 + 15,
                mode: .off
            ),
            HeatingScheduleSlot(
                startMinuteOfDay: 8 * 60 + 15,
                endMinuteOfDay: HeatingSchedule.minutesInDay,
                mode: .off
            )
        ])
    }

    @Test func linkedDocumentMappingPreservesEveryLiveServerPeriod() throws {
        let periods = [
            HeatingSchedulePeriod(start: "00:00", mode: .off),
            HeatingSchedulePeriod(start: "05:30", mode: .heat, targetCelsius: 6),
            HeatingSchedulePeriod(start: "06:00", mode: .heat, targetCelsius: 5),
            HeatingSchedulePeriod(start: "07:00", mode: .off),
            HeatingSchedulePeriod(start: "09:00", mode: .off)
        ]
        let document = HeatingScheduleDocument(
            timezone: "Europe/London",
            programs: [
                HeatingScheduleProgram(
                    id: "everyday-default",
                    enabled: true,
                    days: HeatingScheduleWeekday.allDays,
                    periods: periods
                )
            ],
            revision: "live-revision"
        )

        let linked = try HeatingSchedule.linkedDocument(from: document)
        let exported = try linked.schedule.serverDocument(
            timezone: linked.timezone,
            revision: linked.revision,
            programID: linked.programID
        )

        #expect(linked.schedule.activeSlots.count == periods.count)
        #expect(exported == document)
    }

    @Test func linkedScheduleExportsBackToOneEnabledAllDaysProgram() throws {
        let schedule = HeatingSchedule(activeSlots: [
            HeatingScheduleSlot(
                startMinuteOfDay: 0,
                endMinuteOfDay: 5 * 60 + 30,
                mode: .off
            ),
            HeatingScheduleSlot(
                startMinuteOfDay: 5 * 60 + 30,
                endMinuteOfDay: 8 * 60,
                mode: .heat,
                targetTemperatureCelsius: 20
            ),
            HeatingScheduleSlot(
                startMinuteOfDay: 8 * 60,
                endMinuteOfDay: 8 * 60 + 15,
                mode: .off
            ),
            HeatingScheduleSlot(
                startMinuteOfDay: 8 * 60 + 15,
                endMinuteOfDay: HeatingSchedule.minutesInDay,
                mode: .off
            )
        ])!

        let document = try schedule.serverDocument(
            timezone: "Europe/London",
            revision: "rev-1",
            programID: "everyday-default"
        )

        #expect(document == HeatingScheduleDocument(
            timezone: "Europe/London",
            programs: [
                HeatingScheduleProgram(
                    id: "everyday-default",
                    enabled: true,
                    days: HeatingScheduleWeekday.allDays,
                    periods: [
                        HeatingSchedulePeriod(start: "00:00", mode: .off),
                        HeatingSchedulePeriod(start: "05:30", mode: .heat, targetCelsius: 20),
                        HeatingSchedulePeriod(start: "08:00", mode: .off)
                    ]
                )
            ],
            revision: "rev-1"
        ))
    }

    @Test func linkedDocumentMappingRejectsUnsupportedServerShapes() throws {
        let multiplePrograms = HeatingScheduleDocument(
            timezone: "Europe/London",
            programs: [
                HeatingScheduleProgram(
                    id: "weekday",
                    enabled: true,
                    days: [.mon, .tue, .wed, .thu, .fri],
                    periods: [HeatingSchedulePeriod(start: "00:00", mode: .off)]
                ),
                HeatingScheduleProgram(
                    id: "weekend",
                    enabled: true,
                    days: [.sat, .sun],
                    periods: [HeatingSchedulePeriod(start: "00:00", mode: .off)]
                )
            ],
            revision: "rev"
        )
        let missingAllDays = HeatingScheduleDocument(
            timezone: "Europe/London",
            programs: [
                HeatingScheduleProgram(
                    id: "weekday",
                    enabled: true,
                    days: [.mon, .tue, .wed, .thu, .fri],
                    periods: [HeatingSchedulePeriod(start: "00:00", mode: .off)]
                )
            ],
            revision: "rev"
        )
        let incompatibleShape = HeatingScheduleDocument(
            timezone: "Europe/London",
            programs: [
                HeatingScheduleProgram(
                    id: "everyday-default",
                    enabled: true,
                    days: HeatingScheduleWeekday.allDays,
                    periods: [
                        HeatingSchedulePeriod(start: "00:00", mode: .off),
                        HeatingSchedulePeriod(start: "00:15", mode: .heat, targetCelsius: 19),
                        HeatingSchedulePeriod(start: "00:30", mode: .off),
                        HeatingSchedulePeriod(start: "00:45", mode: .heat, targetCelsius: 20),
                        HeatingSchedulePeriod(start: "01:00", mode: .off)
                    ]
                )
            ],
            revision: "rev"
        )
        let missingHeatTarget = HeatingScheduleDocument(
            timezone: "Europe/London",
            programs: [
                HeatingScheduleProgram(
                    id: "everyday-default",
                    enabled: true,
                    days: HeatingScheduleWeekday.allDays,
                    periods: [
                        HeatingSchedulePeriod(start: "00:00", mode: .off),
                        HeatingSchedulePeriod(start: "05:30", mode: .heat)
                    ]
                )
            ],
            revision: "rev"
        )

        #expect(throws: HeatingScheduleMappingError.programCountUnsupported(2)) {
            try HeatingSchedule.linkedDocument(from: multiplePrograms)
        }

        #expect(throws: HeatingScheduleMappingError.programMustBeEnabledAllDays(
            id: "weekday",
            days: [.mon, .tue, .wed, .thu, .fri],
            enabled: true
        )) {
            try HeatingSchedule.linkedDocument(from: missingAllDays)
        }

        #expect(throws: HeatingScheduleMappingError.incompatibleShape(periodCount: 5)) {
            try HeatingSchedule.linkedDocument(from: incompatibleShape)
        }

        #expect(throws: HeatingScheduleMappingError.heatPeriodMissingTarget(
            programID: "everyday-default",
            start: "05:30"
        )) {
            try HeatingSchedule.linkedDocument(from: missingHeatTarget)
        }
    }
}

private func makeSchedule() -> HeatingSchedule {
    HeatingSchedule(activeSlots: makeLinkedSlots())!
}

private func makeLinkedSlots() -> [HeatingScheduleSlot] {
    [
        HeatingScheduleSlot(
            startMinuteOfDay: 8 * 60,
            endMinuteOfDay: 9 * 60,
            mode: .heat,
            targetTemperatureCelsius: 21
        ),
        HeatingScheduleSlot(
            startMinuteOfDay: 9 * 60,
            endMinuteOfDay: 10 * 60,
            mode: .off
        ),
        HeatingScheduleSlot(
            startMinuteOfDay: 10 * 60,
            endMinuteOfDay: 11 * 60,
            mode: .heat,
            targetTemperatureCelsius: 20
        ),
        HeatingScheduleSlot(
            startMinuteOfDay: 11 * 60,
            endMinuteOfDay: 12 * 60,
            mode: .off
        )
    ]
}
