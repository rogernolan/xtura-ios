import Foundation

struct HeatingScheduleDocument: Codable, Equatable, Sendable {
    var timezone: String
    var programs: [HeatingScheduleProgram]
    var revision: String
}

struct HeatingScheduleProgram: Codable, Equatable, Sendable {
    var id: String
    var enabled: Bool
    var days: [HeatingScheduleWeekday]
    var periods: [HeatingSchedulePeriod]
}

enum HeatingScheduleWeekday: String, Codable, CaseIterable, Equatable, Sendable {
    case mon
    case tue
    case wed
    case thu
    case fri
    case sat
    case sun

    static let allDays: [HeatingScheduleWeekday] = Self.allCases
}

struct HeatingSchedulePeriod: Codable, Equatable, Sendable {
    var start: String
    var mode: HeatingSchedulePeriodMode
    var targetCelsius: Double?

    init(start: String, mode: HeatingSchedulePeriodMode, targetCelsius: Double? = nil) {
        self.start = start
        self.mode = mode
        switch mode {
        case .off:
            self.targetCelsius = nil
        case .heat:
            self.targetCelsius = targetCelsius
        }
    }

    enum CodingKeys: String, CodingKey {
        case start
        case mode
        case targetCelsius = "target_celsius"
    }
}

enum HeatingSchedulePeriodMode: String, Codable, Equatable, Sendable {
    case off
    case heat
}

struct HeatingRuntimeModeDocument: Codable, Equatable, Sendable {
    var mode: HeatingRuntimeMode
    var manualTargetCelsius: Double?
    var boost: HeatingRuntimeBoostDocument?
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case mode
        case manualTargetCelsius = "manual_target_celsius"
        case boost
        case updatedAt = "updated_at"
    }
}

enum HeatingRuntimeMode: String, Codable, Equatable, Sendable {
    case schedule
    case off
    case manual
    case boost
}

struct HeatingRuntimeBoostDocument: Codable, Equatable, Sendable {
    var targetCelsius: Double
    var expiresAt: String
    var resumeMode: HeatingRuntimeMode
    var resumeManualTargetCelsius: Double?

    enum CodingKeys: String, CodingKey {
        case targetCelsius = "target_celsius"
        case expiresAt = "expires_at"
        case resumeMode = "resume_mode"
        case resumeManualTargetCelsius = "resume_manual_target_celsius"
    }
}

struct HeatingModeScheduleRequest: Codable, Equatable, Sendable {}

struct HeatingModeManualRequest: Codable, Equatable, Sendable {
    var targetCelsius: Double

    enum CodingKeys: String, CodingKey {
        case targetCelsius = "target_celsius"
    }
}

struct HeatingModeOffRequest: Codable, Equatable, Sendable {}

struct HeatingValidationFailureDocument: Codable, Equatable, Sendable {
    var error: String
    var details: [HeatingValidationFailureDetail]
}

struct HeatingValidationFailureDetail: Codable, Equatable, Sendable {
    var message: String
}

struct HeatingErrorDocument: Codable, Equatable, Sendable {
    var error: String
}

struct HeatingLinkedScheduleDocument: Equatable, Sendable {
    var timezone: String
    var revision: String
    var programID: String
    var schedule: HeatingSchedule
}
