import Foundation
import Observation

@MainActor
@Observable
final class HeatingFeatureModel {
    enum ServiceState: Equatable {
        case loading
        case notConfigured
        case unavailable(message: String)
        case unsupportedShape(message: String)
        case ready

        var message: String {
            switch self {
            case .loading:
                return "Loading"
            case .notConfigured:
                return "Set the heating service URL in Settings before editing heating. Editing stays unavailable until then."
            case .unavailable(let message), .unsupportedShape(let message):
                return message
            case .ready:
                return "Heating is connected to the server."
            }
        }
    }

    @ObservationIgnored
    private let makeService: @Sendable (URL) throws -> any HeatingServicing

    @ObservationIgnored
    private let baseURLProvider: @MainActor () -> URL?

    var serviceState: ServiceState = .loading
    var schedule: HeatingSchedule?
    var linkedDocument: HeatingLinkedScheduleDocument?
    var runtimeModeDocument: HeatingRuntimeModeDocument?
    var alertMessage: String?

    var canEditSchedule: Bool {
        serviceState == .ready
    }

    var canControlRuntimeMode: Bool {
        canEditSchedule
    }

    var statusTitle: String {
        switch serviceState {
        case .loading:
            return "Loading"
        case .notConfigured:
            return "Not configured"
        case .unavailable:
            return "Service unavailable"
        case .unsupportedShape:
            return "Unsupported schedule"
        case .ready:
            return "Connected"
        }
    }

    var statusMessage: String {
        switch serviceState {
        case .loading:
            return "Fetching the heating schedule and runtime mode from the service."
        default:
            return serviceState.message
        }
    }

    var runtimeModeText: String {
        guard let runtimeModeDocument else {
            return "Unavailable"
        }

        switch runtimeModeDocument.mode {
        case .schedule:
            return "Schedule"
        case .off:
            return "Off"
        case .manual:
            if let manualTargetCelsius = runtimeModeDocument.manualTargetCelsius {
                return "Manual \(Self.formatTemperature(manualTargetCelsius))°C"
            }

            return "Manual"
        case .boost:
            if let boost = runtimeModeDocument.boost {
                return "Boost \(Self.formatTemperature(boost.targetCelsius))°C"
            }

            return "Boost"
        }
    }

    init(
        baseURLProvider: @escaping @MainActor () -> URL? = {
            HeatingServiceSettings().configuredBaseURL
        },
        makeService: @escaping @Sendable (URL) throws -> any HeatingServicing = { baseURL in
            try HeatingService(baseURLString: baseURL.absoluteString)
        }
    ) {
        self.baseURLProvider = baseURLProvider
        self.makeService = makeService
    }

    func load() async {
        alertMessage = nil
        schedule = nil
        linkedDocument = nil
        runtimeModeDocument = nil

        guard let baseURL = baseURLProvider() else {
            serviceState = .notConfigured
            return
        }

        serviceState = .loading

        do {
            let service = try makeService(baseURL)
            let scheduleDocument = try await service.fetchHeatingSchedule()
            let linkedDocument = try HeatingSchedule.linkedDocument(from: scheduleDocument)
            let runtimeModeDocument = try await service.fetchHeatingMode()

            self.linkedDocument = linkedDocument
            schedule = linkedDocument.schedule
            self.runtimeModeDocument = runtimeModeDocument
            serviceState = .ready
        } catch let error as HeatingScheduleMappingError {
            serviceState = .unsupportedShape(message: Self.message(for: error))
        } catch let error as HeatingServiceError {
            serviceState = Self.serviceState(for: error, baseURL: baseURL)
        } catch {
            serviceState = .unavailable(message: error.localizedDescription)
        }
    }

    func save(schedule: HeatingSchedule) async throws {
        guard let linkedDocument else {
            throw HeatingFeatureModelError.notReady(message: statusMessage)
        }

        let service = try makeLoadedService()

        do {
            let document = try schedule.serverDocument(
                timezone: linkedDocument.timezone,
                revision: linkedDocument.revision,
                programID: linkedDocument.programID
            )
            let savedDocument = try await service.saveHeatingSchedule(document)
            try apply(scheduleDocument: savedDocument)
        } catch let error as HeatingServiceError {
            switch error {
            case .validationFailed(let messages):
                throw HeatingFeatureModelError.validationFailed(messages)
            case .conflict(let message):
                await load()
                throw HeatingFeatureModelError.conflict(message: message)
            default:
                let state = Self.serviceState(for: error, baseURL: linkedDocumentBaseURL())
                serviceState = state
                throw HeatingFeatureModelError.unavailable(message: state.message)
            }
        } catch let error as HeatingScheduleMappingError {
            let message = Self.message(for: error)
            serviceState = .unsupportedShape(message: message)
            throw HeatingFeatureModelError.unsupportedShape(message: message)
        }
    }

    func setRuntimeModeSchedule() async throws {
        let service = try makeLoadedService()

        do {
            let modeDocument = try await service.setHeatingModeSchedule()
            runtimeModeDocument = modeDocument
        } catch let error as HeatingServiceError {
            let state = Self.serviceState(for: error, baseURL: linkedDocumentBaseURL())
            serviceState = state
            throw HeatingFeatureModelError.unavailable(message: state.message)
        }
    }

    func setRuntimeModeOff() async throws {
        let service = try makeLoadedService()

        do {
            let modeDocument = try await service.setHeatingModeOff()
            runtimeModeDocument = modeDocument
        } catch let error as HeatingServiceError {
            let state = Self.serviceState(for: error, baseURL: linkedDocumentBaseURL())
            serviceState = state
            throw HeatingFeatureModelError.unavailable(message: state.message)
        }
    }

    private func makeLoadedService() throws -> any HeatingServicing {
        guard let baseURL = baseURLProvider() else {
            serviceState = .notConfigured
            throw HeatingFeatureModelError.notConfigured
        }

        do {
            return try makeService(baseURL)
        } catch {
            serviceState = .unavailable(message: error.localizedDescription)
            throw HeatingFeatureModelError.unavailable(message: error.localizedDescription)
        }
    }

    private func linkedDocumentBaseURL() -> URL? {
        baseURLProvider()
    }

    private func apply(scheduleDocument: HeatingScheduleDocument) throws {
        let linkedDocument = try HeatingSchedule.linkedDocument(from: scheduleDocument)
        self.linkedDocument = linkedDocument
        schedule = linkedDocument.schedule
        serviceState = .ready
    }

    private static func serviceState(for error: HeatingServiceError, baseURL: URL?) -> ServiceState {
        switch error {
        case .invalidBaseURL:
            return .notConfigured
        case .invalidResponse:
            return .unavailable(message: "The heating service returned an invalid response.")
        case .transport(let underlyingError):
            return .unavailable(message: transportMessage(for: underlyingError, baseURL: baseURL))
        case .decoding:
            return .unavailable(message: "The heating service returned data JonesControl could not read.")
        case .conflict(let message):
            return .unavailable(message: message)
        case .validationFailed(let messages):
            return .unavailable(message: messages.joined(separator: "\n"))
        case .server(let statusCode, let message):
            return .unavailable(message: "\(statusCode): \(message)")
        }
    }

    private static func transportMessage(for error: Error, baseURL: URL?) -> String {
        let host = baseURL?.host ?? "the configured host"

        guard let urlError = error as? URLError else {
            return "The heating service at \(host) could not be reached: \(error.localizedDescription)"
        }

        switch urlError.code {
        case .appTransportSecurityRequiresSecureConnection:
            return "JonesControl was blocked from using plain HTTP to reach \(host). Check the app's transport security settings."
        case .cannotFindHost, .dnsLookupFailed:
            return "JonesControl could not resolve \(host). Check the hostname in Settings and confirm Tailscale DNS or MagicDNS is working on the phone."
        case .cannotConnectToHost:
            return "JonesControl resolved \(host) but could not connect to it on the network. Check that the Pi service is listening and the Tailscale route is active."
        case .timedOut:
            return "JonesControl reached out to \(host) but the request timed out. The Pi may be slow to respond over Tailscale or cellular."
        case .notConnectedToInternet, .networkConnectionLost, .internationalRoamingOff:
            return "JonesControl does not currently have a working network path to \(host). Check the phone connection and that Tailscale is active."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
            return "JonesControl hit a TLS or certificate problem while reaching \(host): \(urlError.localizedDescription)"
        default:
            return "The heating service at \(host) could not be reached: \(urlError.localizedDescription)"
        }
    }

    private static func message(for error: HeatingScheduleMappingError) -> String {
        switch error {
        case .programCountUnsupported(let count):
            return "JonesControl can only edit one heating program, but the server returned \(count)."
        case .programMustBeEnabledAllDays(let id, let days, let enabled):
            let daysText = days.map(\.rawValue).joined(separator: ", ")
            return "Program \(id) must be enabled and cover all days, but the server returned enabled=\(enabled) for days=\(daysText)."
        case .periodsEmpty(let programID):
            return "Program \(programID) does not contain any periods."
        case .firstPeriodMustStartAtMidnight(let programID):
            return "Program \(programID) must start at 00:00."
        case .periodsOutOfOrder(let programID, let start):
            return "Program \(programID) has periods out of time order near \(start)."
        case .heatPeriodMissingTarget(let programID, let start):
            return "Program \(programID) has a heat period at \(start) without a target temperature."
        case .incompatibleShape(let periodCount):
            return "The server returned \(periodCount) periods, which does not fit the linked four-slot editor."
        case .invalidTime(let time):
            return "The server returned an invalid time value: \(time)."
        case .exportFailed(let exportValidationError):
            return exportValidationError.errors.map(Self.message(for:)).joined(separator: "\n")
        }
    }

    private static func message(for error: HeatingScheduleValidationError) -> String {
        switch error {
        case .startMinuteOutOfRange:
            return "A slot start time was out of range."
        case .endMinuteOutOfRange:
            return "A slot end time was out of range."
        case .invalidTimeRange:
            return "A slot end time must be later than its start time."
        case .missingTargetTemperature:
            return "Heat slots need a target temperature."
        case .overlappingSlots:
            return "The schedule still overlaps after the edit."
        }
    }

    static func message(for error: HeatingFeatureModelError) -> String {
        switch error {
        case .notConfigured:
            return ServiceState.notConfigured.message
        case .notReady(let message), .unavailable(let message), .unsupportedShape(let message), .conflict(let message):
            return message
        case .validationFailed(let messages):
            return messages.joined(separator: "\n")
        }
    }

    private static func formatTemperature(_ temperature: Double) -> String {
        if temperature.rounded(.towardZero) == temperature {
            return String(format: "%.0f", temperature)
        }

        return String(format: "%.1f", temperature)
    }
}

enum HeatingFeatureModelError: Error, Equatable, Sendable {
    case notConfigured
    case notReady(message: String)
    case unavailable(message: String)
    case unsupportedShape(message: String)
    case validationFailed([String])
    case conflict(message: String)
}
