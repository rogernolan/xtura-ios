import Foundation
import Testing
@testable import JonesControl

@MainActor
struct HeatingFeatureModelTests {
    @Test func loadShowsNotConfiguredWhenBaseURLIsMissing() async throws {
        let model = HeatingFeatureModel(baseURLProvider: { nil })

        await model.load()

        #expect(model.serviceState == .notConfigured)
        #expect(model.schedule == nil)
        #expect(model.runtimeModeDocument == nil)
        #expect(model.canEditSchedule == false)
        #expect(model.statusMessage.contains("Settings"))
    }

    @Test func loadImportsLinkedScheduleAndRuntimeModeFromTheServer() async throws {
        let service = HeatingServiceStub(
            fetchSchedule: {
                HeatingScheduleDocument(
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
                )
            },
            fetchMode: {
                HeatingRuntimeModeDocument(
                    mode: .manual,
                    manualTargetCelsius: 19,
                    boost: nil,
                    updatedAt: "2026-04-22T10:20:00Z"
                )
            }
        )
        let model = HeatingFeatureModel(
            baseURLProvider: { URL(string: "http://example.com") },
            makeService: { _ in service }
        )

        await model.load()

        #expect(service.fetchHeatingScheduleCallCount == 1)
        #expect(service.fetchHeatingModeCallCount == 1)
        #expect(model.serviceState == .ready)
        #expect(model.linkedDocument?.timezone == "Europe/London")
        #expect(model.linkedDocument?.revision == "rev-1")
        #expect(model.schedule?.activeSlots.count == 4)
        #expect(model.runtimeModeText == "Manual 19°C")
    }

    @Test func loadSurfacesUnsupportedServerShapesCleanly() async throws {
        let service = HeatingServiceStub(
            fetchSchedule: {
                HeatingScheduleDocument(
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
                    revision: "rev-1"
                )
            },
            fetchMode: {
                HeatingRuntimeModeDocument(
                    mode: .schedule,
                    manualTargetCelsius: nil,
                    boost: nil,
                    updatedAt: "2026-04-22T10:20:00Z"
                )
            }
        )
        let model = HeatingFeatureModel(
            baseURLProvider: { URL(string: "http://example.com") },
            makeService: { _ in service }
        )

        await model.load()

        #expect(service.fetchHeatingScheduleCallCount == 1)
        #expect(service.fetchHeatingModeCallCount == 0)
        #expect(model.serviceState == .unsupportedShape(message: "JonesControl can only edit one heating program, but the server returned 2."))
        #expect(model.schedule == nil)
    }

    @Test func loadExplainsDNSFailuresWithHostContext() async throws {
        let service = HeatingServiceStub(
            fetchSchedule: {
                throw HeatingServiceError.transport(URLError(.cannotFindHost))
            }
        )
        let model = HeatingFeatureModel(
            baseURLProvider: { URL(string: "http://jones-pi.taile19bc2.ts.net:8080") },
            makeService: { _ in service }
        )

        await model.load()

        #expect(model.statusTitle == "Service unavailable")
        #expect(model.statusMessage.contains("could not resolve"))
        #expect(model.statusMessage.contains("jones-pi.taile19bc2.ts.net"))
        #expect(model.statusMessage.contains("MagicDNS"))
    }

    @Test func loadExplainsTimeoutsAsSlowNetworkResponses() async throws {
        let service = HeatingServiceStub(
            fetchSchedule: {
                throw HeatingServiceError.transport(URLError(.timedOut))
            }
        )
        let model = HeatingFeatureModel(
            baseURLProvider: { URL(string: "http://jones-pi.taile19bc2.ts.net:8080") },
            makeService: { _ in service }
        )

        await model.load()

        #expect(model.statusTitle == "Service unavailable")
        #expect(model.statusMessage.contains("timed out"))
        #expect(model.statusMessage.contains("Tailscale"))
    }

    @Test func saveScheduleUsesTheServerRevisionAndRefreshesFromTheResponse() async throws {
        let responseDocument = HeatingScheduleDocument(
            timezone: "Europe/London",
            programs: [
                HeatingScheduleProgram(
                    id: "everyday-default",
                    enabled: true,
                    days: HeatingScheduleWeekday.allDays,
                    periods: [
                        HeatingSchedulePeriod(start: "00:00", mode: .off),
                        HeatingSchedulePeriod(start: "05:30", mode: .heat, targetCelsius: 21),
                        HeatingSchedulePeriod(start: "08:00", mode: .off)
                    ]
                )
            ],
            revision: "rev-2"
        )
        let service = HeatingServiceStub(
            fetchSchedule: {
                HeatingScheduleDocument(
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
                )
            },
            fetchMode: {
                HeatingRuntimeModeDocument(
                    mode: .schedule,
                    manualTargetCelsius: nil,
                    boost: nil,
                    updatedAt: "2026-04-22T10:20:00Z"
                )
            },
            saveSchedule: { document in
                document
            }
        )
        let model = HeatingFeatureModel(
            baseURLProvider: { URL(string: "http://example.com") },
            makeService: { _ in service }
        )

        await model.load()
        guard model.schedule != nil else {
            Issue.record("Expected schedule to load.")
            return
        }

        let updatedSchedule = HeatingSchedule(
            activeSlots: [
                HeatingScheduleSlot(
                    startMinuteOfDay: 0,
                    endMinuteOfDay: 5 * 60 + 30,
                    mode: .off
                ),
                HeatingScheduleSlot(
                    startMinuteOfDay: 5 * 60 + 30,
                    endMinuteOfDay: 8 * 60,
                    mode: .heat,
                    targetTemperatureCelsius: 21
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
            ]
        )!

        service.saveScheduleHandler = { document in
            #expect(document.revision == "rev-1")
            #expect(document.programs[0].periods[1].targetCelsius == 21)
            return responseDocument
        }

        try await model.save(schedule: updatedSchedule)

        #expect(service.saveHeatingScheduleCallCount == 1)
        #expect(model.linkedDocument?.revision == "rev-2")
        #expect(model.schedule == updatedSchedule)
        #expect(model.serviceState == .ready)
    }

    @Test func saveScheduleSurfacesValidationFailuresAndKeepsTheScheduleReady() async throws {
        let service = HeatingServiceStub(
            fetchSchedule: {
                HeatingScheduleDocument(
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
                )
            },
            fetchMode: {
                HeatingRuntimeModeDocument(
                    mode: .schedule,
                    manualTargetCelsius: nil,
                    boost: nil,
                    updatedAt: "2026-04-22T10:20:00Z"
                )
            },
            saveSchedule: { _ in
                throw HeatingServiceError.validationFailed(["automation.heating_programs[0]: heat periods must set target_celsius"])
            }
        )
        let model = HeatingFeatureModel(
            baseURLProvider: { URL(string: "http://example.com") },
            makeService: { _ in service }
        )

        await model.load()
        guard let schedule = model.schedule else {
            Issue.record("Expected schedule to load.")
            return
        }

        do {
            try await model.save(schedule: schedule)
            Issue.record("Expected validation error.")
        } catch let error as HeatingFeatureModelError {
            guard case .validationFailed(let messages) = error else {
                Issue.record("Expected validation failure, got \(error).")
                return
            }

            #expect(messages == ["automation.heating_programs[0]: heat periods must set target_celsius"])
        }

        #expect(model.serviceState == HeatingFeatureModel.ServiceState.ready)
        #expect(service.saveHeatingScheduleCallCount == 1)
    }

    @Test func saveScheduleRefreshesAfterConflict() async throws {
        let service = HeatingServiceStub(
            fetchSchedule: {
                HeatingScheduleDocument(
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
                )
            },
            fetchMode: {
                HeatingRuntimeModeDocument(
                    mode: .schedule,
                    manualTargetCelsius: nil,
                    boost: nil,
                    updatedAt: "2026-04-22T10:20:00Z"
                )
            },
            saveSchedule: { _ in
                throw HeatingServiceError.conflict(message: "schedule revision conflict")
            }
        )
        let model = HeatingFeatureModel(
            baseURLProvider: { URL(string: "http://example.com") },
            makeService: { _ in service }
        )

        await model.load()
        guard let schedule = model.schedule else {
            Issue.record("Expected schedule to load.")
            return
        }

        do {
            try await model.save(schedule: schedule)
            Issue.record("Expected conflict error.")
        } catch let error as HeatingFeatureModelError {
            guard case .conflict(let message) = error else {
                Issue.record("Expected conflict, got \(error).")
                return
            }

            #expect(message == "schedule revision conflict")
        }

        #expect(service.fetchHeatingScheduleCallCount == 2)
        #expect(model.serviceState == HeatingFeatureModel.ServiceState.ready)
    }

    @Test func runtimeModeActionsRoundTripToTheService() async throws {
        let service = HeatingServiceStub(
            fetchSchedule: {
                HeatingScheduleDocument(
                    timezone: "Europe/London",
                    programs: [
                        HeatingScheduleProgram(
                            id: "everyday-default",
                            enabled: true,
                            days: HeatingScheduleWeekday.allDays,
                            periods: [
                                HeatingSchedulePeriod(start: "00:00", mode: .off)
                            ]
                        )
                    ],
                    revision: "rev-1"
                )
            },
            fetchMode: {
                HeatingRuntimeModeDocument(
                    mode: .schedule,
                    manualTargetCelsius: nil,
                    boost: nil,
                    updatedAt: "2026-04-22T10:20:00Z"
                )
            },
            setModeSchedule: {
                HeatingRuntimeModeDocument(
                    mode: .schedule,
                    manualTargetCelsius: nil,
                    boost: nil,
                    updatedAt: "2026-04-22T10:30:00Z"
                )
            },
            setModeManual: { targetCelsius in
                HeatingRuntimeModeDocument(
                    mode: .manual,
                    manualTargetCelsius: targetCelsius,
                    boost: nil,
                    updatedAt: "2026-04-22T10:30:30Z"
                )
            },
            setModeOff: {
                HeatingRuntimeModeDocument(
                    mode: .off,
                    manualTargetCelsius: nil,
                    boost: nil,
                    updatedAt: "2026-04-22T10:31:00Z"
                )
            },
            setModeBoost: { targetCelsius, durationMinutes in
                #expect(durationMinutes == 60)
                return HeatingRuntimeModeDocument(
                    mode: .boost,
                    manualTargetCelsius: nil,
                    boost: HeatingRuntimeBoostDocument(
                        targetCelsius: targetCelsius,
                        expiresAt: "2026-04-24T09:33:00Z",
                        resumeMode: .off,
                        resumeManualTargetCelsius: nil
                    ),
                    updatedAt: "2026-04-24T08:33:00Z"
                )
            },
            cancelBoost: {
                HeatingRuntimeModeDocument(
                    mode: .schedule,
                    manualTargetCelsius: nil,
                    boost: nil,
                    updatedAt: "2026-04-24T08:45:00Z"
                )
            }
        )
        let model = HeatingFeatureModel(
            baseURLProvider: { URL(string: "http://example.com") },
            makeService: { _ in service }
        )

        await model.load()
        try await model.setRuntimeModeOff()
        #expect(service.setHeatingModeOffCallCount == 1)
        #expect(model.runtimeModeDocument?.mode == .off)

        try await model.setRuntimeModeManual(targetCelsius: 19.5)
        #expect(service.setHeatingModeManualCallCount == 1)
        #expect(service.lastManualTargetCelsius == 19.5)
        #expect(model.runtimeModeDocument?.mode == .manual)
        #expect(model.runtimeModeDocument?.manualTargetCelsius == 19.5)

        try await model.setRuntimeModeSchedule()
        #expect(service.setHeatingModeScheduleCallCount == 1)
        #expect(model.runtimeModeDocument?.mode == .schedule)

        try await model.setRuntimeModeBoost(targetCelsius: 21.5, durationMinutes: 60)
        #expect(service.setHeatingModeBoostCallCount == 1)
        #expect(service.lastBoostTargetCelsius == 21.5)
        #expect(service.lastBoostDurationMinutes == 60)
        #expect(model.runtimeModeDocument?.mode == .boost)
        #expect(model.activeBoostTargetCelsius == 21.5)

        try await model.cancelRuntimeModeBoost()
        #expect(service.cancelHeatingModeBoostCallCount == 1)
        #expect(model.runtimeModeDocument?.mode == .schedule)
    }

    @Test func runtimeModeCoalescesQueuedChangesWhileARequestIsInFlight() async throws {
        let pendingOff = PendingRuntimeModeResponse()
        let service = HeatingServiceStub(
            fetchSchedule: {
                HeatingScheduleDocument(
                    timezone: "Europe/London",
                    programs: [
                        HeatingScheduleProgram(
                            id: "everyday-default",
                            enabled: true,
                            days: HeatingScheduleWeekday.allDays,
                            periods: [
                                HeatingSchedulePeriod(start: "00:00", mode: .off)
                            ]
                        )
                    ],
                    revision: "rev-1"
                )
            },
            fetchMode: {
                HeatingRuntimeModeDocument(
                    mode: .schedule,
                    manualTargetCelsius: nil,
                    boost: nil,
                    updatedAt: "2026-04-22T10:20:00Z"
                )
            },
            setModeSchedule: {
                HeatingRuntimeModeDocument(
                    mode: .schedule,
                    manualTargetCelsius: nil,
                    boost: nil,
                    updatedAt: "2026-04-22T10:31:00Z"
                )
            },
            setModeManual: { targetCelsius in
                HeatingRuntimeModeDocument(
                    mode: .manual,
                    manualTargetCelsius: targetCelsius,
                    boost: nil,
                    updatedAt: "2026-04-22T10:30:30Z"
                )
            },
            setModeOff: {
                try await pendingOff.waitForResponse()
            }
        )
        let model = HeatingFeatureModel(
            baseURLProvider: { URL(string: "http://example.com") },
            makeService: { _ in service }
        )

        await model.load()

        let offTask = Task {
            try await model.setRuntimeModeOff()
        }

        await pendingOff.waitUntilRequested()
        #expect(model.isChangingRuntimeMode)

        try await model.setRuntimeModeManual(targetCelsius: 18.5)
        try await model.setRuntimeModeSchedule()

        #expect(service.setHeatingModeOffCallCount == 1)
        #expect(service.setHeatingModeManualCallCount == 0)
        #expect(service.setHeatingModeScheduleCallCount == 0)

        await pendingOff.resume(
            with: HeatingRuntimeModeDocument(
                mode: .off,
                manualTargetCelsius: nil,
                boost: nil,
                updatedAt: "2026-04-22T10:30:00Z"
            )
        )

        try await offTask.value

        #expect(service.setHeatingModeOffCallCount == 1)
        #expect(service.setHeatingModeManualCallCount == 0)
        #expect(service.setHeatingModeScheduleCallCount == 1)
        #expect(model.runtimeModeDocument?.mode == .schedule)
        #expect(model.isChangingRuntimeMode == false)
    }
}

actor PendingRuntimeModeResponse {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<HeatingRuntimeModeDocument, Error>?

    func waitUntilRequested() async {
        if started {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func waitForResponse() async throws -> HeatingRuntimeModeDocument {
        started = true
        let waiters = waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with document: HeatingRuntimeModeDocument) {
        continuation?.resume(returning: document)
        continuation = nil
    }
}

private final class HeatingServiceStub: HeatingServicing {
    var fetchScheduleHandler: () async throws -> HeatingScheduleDocument
    var fetchModeHandler: () async throws -> HeatingRuntimeModeDocument
    var saveScheduleHandler: (HeatingScheduleDocument) async throws -> HeatingScheduleDocument
    var setModeScheduleHandler: () async throws -> HeatingRuntimeModeDocument
    var setModeManualHandler: (Double) async throws -> HeatingRuntimeModeDocument
    var setModeOffHandler: () async throws -> HeatingRuntimeModeDocument
    var setModeBoostHandler: (Double, Int) async throws -> HeatingRuntimeModeDocument
    var cancelBoostHandler: () async throws -> HeatingRuntimeModeDocument

    private(set) var fetchHeatingScheduleCallCount = 0
    private(set) var fetchHeatingModeCallCount = 0
    private(set) var saveHeatingScheduleCallCount = 0
    private(set) var setHeatingModeScheduleCallCount = 0
    private(set) var setHeatingModeManualCallCount = 0
    private(set) var setHeatingModeOffCallCount = 0
    private(set) var setHeatingModeBoostCallCount = 0
    private(set) var cancelHeatingModeBoostCallCount = 0
    private(set) var lastManualTargetCelsius: Double?
    private(set) var lastBoostTargetCelsius: Double?
    private(set) var lastBoostDurationMinutes: Int?
    private(set) var savedDocuments: [HeatingScheduleDocument] = []

    init(
        fetchSchedule: @escaping () async throws -> HeatingScheduleDocument,
        fetchMode: @escaping () async throws -> HeatingRuntimeModeDocument = {
            HeatingRuntimeModeDocument(mode: .schedule, manualTargetCelsius: nil, boost: nil, updatedAt: "")
        },
        saveSchedule: @escaping (HeatingScheduleDocument) async throws -> HeatingScheduleDocument = { $0 },
        setModeSchedule: @escaping () async throws -> HeatingRuntimeModeDocument = {
            HeatingRuntimeModeDocument(mode: .schedule, manualTargetCelsius: nil, boost: nil, updatedAt: "")
        },
        setModeManual: @escaping (Double) async throws -> HeatingRuntimeModeDocument = { targetCelsius in
            HeatingRuntimeModeDocument(mode: .manual, manualTargetCelsius: targetCelsius, boost: nil, updatedAt: "")
        },
        setModeOff: @escaping () async throws -> HeatingRuntimeModeDocument = {
            HeatingRuntimeModeDocument(mode: .off, manualTargetCelsius: nil, boost: nil, updatedAt: "")
        },
        setModeBoost: @escaping (Double, Int) async throws -> HeatingRuntimeModeDocument = { targetCelsius, _ in
            HeatingRuntimeModeDocument(
                mode: .boost,
                manualTargetCelsius: nil,
                boost: HeatingRuntimeBoostDocument(
                    targetCelsius: targetCelsius,
                    expiresAt: "2026-04-24T09:32:00Z",
                    resumeMode: .schedule,
                    resumeManualTargetCelsius: nil
                ),
                updatedAt: ""
            )
        },
        cancelBoost: @escaping () async throws -> HeatingRuntimeModeDocument = {
            HeatingRuntimeModeDocument(mode: .schedule, manualTargetCelsius: nil, boost: nil, updatedAt: "")
        }
    ) {
        self.fetchScheduleHandler = fetchSchedule
        self.fetchModeHandler = fetchMode
        self.saveScheduleHandler = saveSchedule
        self.setModeScheduleHandler = setModeSchedule
        self.setModeManualHandler = setModeManual
        self.setModeOffHandler = setModeOff
        self.setModeBoostHandler = setModeBoost
        self.cancelBoostHandler = cancelBoost
    }

    func fetchHeatingSchedule() async throws -> HeatingScheduleDocument {
        fetchHeatingScheduleCallCount += 1
        return try await fetchScheduleHandler()
    }

    func saveHeatingSchedule(_ document: HeatingScheduleDocument) async throws -> HeatingScheduleDocument {
        saveHeatingScheduleCallCount += 1
        savedDocuments.append(document)
        return try await saveScheduleHandler(document)
    }

    func fetchHeatingMode() async throws -> HeatingRuntimeModeDocument {
        fetchHeatingModeCallCount += 1
        return try await fetchModeHandler()
    }

    func setHeatingModeSchedule() async throws -> HeatingRuntimeModeDocument {
        setHeatingModeScheduleCallCount += 1
        return try await setModeScheduleHandler()
    }

    func setHeatingModeManual(targetCelsius: Double) async throws -> HeatingRuntimeModeDocument {
        setHeatingModeManualCallCount += 1
        lastManualTargetCelsius = targetCelsius
        return try await setModeManualHandler(targetCelsius)
    }

    func setHeatingModeOff() async throws -> HeatingRuntimeModeDocument {
        setHeatingModeOffCallCount += 1
        return try await setModeOffHandler()
    }

    func setHeatingModeBoost(targetCelsius: Double, durationMinutes: Int) async throws -> HeatingRuntimeModeDocument {
        setHeatingModeBoostCallCount += 1
        lastBoostTargetCelsius = targetCelsius
        lastBoostDurationMinutes = durationMinutes
        return try await setModeBoostHandler(targetCelsius, durationMinutes)
    }

    func cancelHeatingModeBoost() async throws -> HeatingRuntimeModeDocument {
        cancelHeatingModeBoostCallCount += 1
        return try await cancelBoostHandler()
    }
}
