import Foundation

protocol HeatingServicing {
    func fetchHeatingSchedule() async throws -> HeatingScheduleDocument
    func saveHeatingSchedule(_ document: HeatingScheduleDocument) async throws -> HeatingScheduleDocument
    func fetchHeatingMode() async throws -> HeatingRuntimeModeDocument
    func setHeatingModeSchedule() async throws -> HeatingRuntimeModeDocument
    func setHeatingModeManual(targetCelsius: Double) async throws -> HeatingRuntimeModeDocument
    func setHeatingModeOff() async throws -> HeatingRuntimeModeDocument
    func setHeatingModeBoost(targetCelsius: Double, durationMinutes: Int) async throws -> HeatingRuntimeModeDocument
    func cancelHeatingModeBoost() async throws -> HeatingRuntimeModeDocument
}

struct HeatingService {
    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    nonisolated init(baseURLString: String, session: URLSession = Self.makeSession()) throws {
        guard let url = URL(string: baseURLString) else {
            throw HeatingServiceError.invalidBaseURL(baseURLString)
        }

        self.session = session
        self.baseURL = url
    }

    func fetchHeatingSchedule() async throws -> HeatingScheduleDocument {
        try await sendRequest(
            path: "/v1/automation/heating-schedule",
            method: "GET",
            responseType: HeatingScheduleDocument.self
        )
    }

    func saveHeatingSchedule(_ document: HeatingScheduleDocument) async throws -> HeatingScheduleDocument {
        try await sendRequest(
            path: "/v1/automation/heating-schedule",
            method: "PUT",
            body: document,
            responseType: HeatingScheduleDocument.self
        )
    }

    func fetchHeatingMode() async throws -> HeatingRuntimeModeDocument {
        try await sendRequest(
            path: "/v1/heating/mode",
            method: "GET",
            responseType: HeatingRuntimeModeDocument.self
        )
    }

    func setHeatingModeSchedule() async throws -> HeatingRuntimeModeDocument {
        try await sendRequest(
            path: "/v1/heating/mode/schedule",
            method: "POST",
            responseType: HeatingRuntimeModeDocument.self
        )
    }

    func setHeatingModeManual(targetCelsius: Double) async throws -> HeatingRuntimeModeDocument {
        try await sendRequest(
            path: "/v1/heating/mode/manual",
            method: "POST",
            body: HeatingModeManualRequest(targetCelsius: targetCelsius),
            responseType: HeatingRuntimeModeDocument.self
        )
    }

    func setHeatingModeOff() async throws -> HeatingRuntimeModeDocument {
        try await sendRequest(
            path: "/v1/heating/mode/off",
            method: "POST",
            responseType: HeatingRuntimeModeDocument.self
        )
    }

    func setHeatingModeBoost(targetCelsius: Double, durationMinutes: Int) async throws -> HeatingRuntimeModeDocument {
        try await sendRequest(
            path: "/v1/heating/mode/boost",
            method: "POST",
            body: HeatingModeBoostRequest(
                targetCelsius: targetCelsius,
                durationMinutes: durationMinutes
            ),
            responseType: HeatingRuntimeModeDocument.self
        )
    }

    func cancelHeatingModeBoost() async throws -> HeatingRuntimeModeDocument {
        try await sendRequest(
            path: "/v1/heating/mode/boost/cancel",
            method: "POST",
            responseType: HeatingRuntimeModeDocument.self
        )
    }

    private func sendRequest<ResponseBody: Decodable>(
        path: String,
        method: String,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        let request = try makeRequest(path: path, method: method)
        return try await execute(request, responseType: responseType)
    }

    private func sendRequest<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        method: String,
        body: RequestBody?,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        let request = try makeRequest(path: path, method: method, body: body)
        return try await execute(request, responseType: responseType)
    }

    private func execute<ResponseBody: Decodable>(
        _ request: URLRequest,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error is CancellationError {
                throw error
            }

            throw HeatingServiceError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HeatingServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(ResponseBody.self, from: data)
            } catch {
                throw HeatingServiceError.decoding(error)
            }
        case 400:
            if let validationFailure = try? decoder.decode(HeatingValidationFailureDocument.self, from: data),
               validationFailure.error == "validation_failed" {
                throw HeatingServiceError.validationFailed(validationFailure.details.map(\.message))
            }

            let message = (try? decoder.decode(HeatingErrorDocument.self, from: data).error) ?? "bad request"
            throw HeatingServiceError.server(statusCode: 400, message: message)
        case 409:
            let message = (try? decoder.decode(HeatingErrorDocument.self, from: data).error) ?? "conflict"
            throw HeatingServiceError.conflict(message: message)
        default:
            let message = (try? decoder.decode(HeatingErrorDocument.self, from: data).error) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw HeatingServiceError.server(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeRequest<RequestBody: Encodable>(
        path: String,
        method: String,
        body: RequestBody?
    ) throws -> URLRequest {
        var request = try makeRequest(path: path, method: method)

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    nonisolated private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}

extension HeatingService: HeatingServicing {}

enum HeatingServiceError: Error {
    case invalidBaseURL(String)
    case invalidResponse
    case transport(Error)
    case decoding(Error)
    case conflict(message: String)
    case validationFailed([String])
    case server(statusCode: Int, message: String)
}
