import Foundation

struct LightingState: Codable, Equatable, Sendable {
    var externalKnown: Bool
    var externalOn: Bool
    var flashInProgress: Bool
    var lastCommandError: String?
    var lastUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case externalKnown = "external_known"
        case externalOn = "external_on"
        case flashInProgress = "flash_in_progress"
        case lastCommandError = "last_command_error"
        case lastUpdatedAt = "last_updated_at"
    }
}

struct LightingFlashRequest: Codable, Equatable, Sendable {
    var count: Int
}

struct LightingErrorDocument: Codable, Equatable, Sendable {
    var error: String
}
