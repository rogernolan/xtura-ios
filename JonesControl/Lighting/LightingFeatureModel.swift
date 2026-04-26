import Foundation
import Observation

@MainActor
@Observable
final class LightingFeatureModel {
    static let minimumFlashCount = 1
    static let maximumFlashCount = 5

    @ObservationIgnored
    private let makeService: @Sendable (URL) throws -> any LightingServicing

    @ObservationIgnored
    private let baseURLProvider: @MainActor () -> URL?

    var isFlashing = false
    var lastState: LightingState?
    var lastFlashMessage: String?

    init(
        baseURLProvider: @escaping @MainActor () -> URL? = {
            HeatingServiceSettings().configuredBaseURL
        },
        makeService: @escaping @Sendable (URL) throws -> any LightingServicing = { baseURL in
            try LightingService(baseURLString: baseURL.absoluteString)
        }
    ) {
        self.baseURLProvider = baseURLProvider
        self.makeService = makeService
    }

    func flashExternalLights(count: Int) async throws {
        guard Self.validFlashCountRange.contains(count) else {
            throw LightingFeatureModelError.invalidFlashCount
        }

        guard let baseURL = baseURLProvider() else {
            throw LightingFeatureModelError.notConfigured
        }

        let service: any LightingServicing
        do {
            service = try makeService(baseURL)
        } catch {
            throw LightingFeatureModelError.unavailable(message: error.localizedDescription)
        }

        isFlashing = true
        defer { isFlashing = false }

        do {
            lastState = try await service.flashExternalLights(count: count)
            lastFlashMessage = Self.successMessage(for: count)
        } catch let error as LightingServiceError {
            throw Self.featureError(for: error, baseURL: baseURL)
        }
    }

    static var validFlashCountRange: ClosedRange<Int> {
        minimumFlashCount...maximumFlashCount
    }

    nonisolated static func message(for error: LightingFeatureModelError) -> String {
        switch error {
        case .notConfigured:
            return "Set the service URL in Settings before flashing external lights."
        case .invalidFlashCount:
            return "Flash count must be between 1 and 5."
        case .flashInProgress:
            return "The external lights are already flashing."
        case .unavailable(let message):
            return message
        }
    }

    private static func successMessage(for count: Int) -> String {
        if count == 1 {
            return "External lights flashed once."
        }

        return "External lights flashed \(count) times."
    }

    private static func featureError(for error: LightingServiceError, baseURL: URL?) -> LightingFeatureModelError {
        switch error {
        case .invalidBaseURL:
            return .notConfigured
        case .invalidResponse:
            return .unavailable(message: "The lighting service returned an invalid response.")
        case .transport(let underlyingError):
            return .unavailable(message: transportMessage(for: underlyingError, baseURL: baseURL))
        case .decoding:
            return .unavailable(message: "The lighting service returned data JonesControl could not read.")
        case .invalidFlashCount:
            return .invalidFlashCount
        case .flashInProgress:
            return .flashInProgress
        case .server(let statusCode, let message):
            return .unavailable(message: "\(statusCode): \(message)")
        }
    }

    private static func transportMessage(for error: Error, baseURL: URL?) -> String {
        let host = baseURL?.host ?? "the configured host"

        guard let urlError = error as? URLError else {
            return "The lighting service at \(host) could not be reached: \(error.localizedDescription)"
        }

        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed:
            return "JonesControl could not resolve \(host). Check the hostname in Settings and confirm Tailscale DNS or MagicDNS is working on the phone."
        case .cannotConnectToHost:
            return "JonesControl resolved \(host) but could not connect to it on the network. Check that the Pi service is listening and the Tailscale route is active."
        case .timedOut:
            return "JonesControl reached out to \(host) but the request timed out. The Pi may be slow to respond over Tailscale or cellular."
        case .notConnectedToInternet, .networkConnectionLost, .internationalRoamingOff:
            return "JonesControl does not currently have a working network path to \(host). Check the phone connection and that Tailscale is active."
        default:
            return "The lighting service at \(host) could not be reached: \(urlError.localizedDescription)"
        }
    }
}

enum LightingFeatureModelError: Error, Equatable, Sendable {
    case notConfigured
    case invalidFlashCount
    case flashInProgress
    case unavailable(message: String)
}
