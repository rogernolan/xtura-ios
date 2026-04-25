import Foundation

protocol LightingServicing {
    func flashExternalLights(count: Int) async throws -> LightingState
}

struct LightingService {
    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    nonisolated init(baseURLString: String, session: URLSession = Self.makeSession()) throws {
        guard let url = URL(string: baseURLString) else {
            throw LightingServiceError.invalidBaseURL(baseURLString)
        }

        self.session = session
        self.baseURL = url
    }

    func flashExternalLights(count: Int) async throws -> LightingState {
        try await sendRequest(
            path: "/v1/lights/external/flash",
            method: "POST",
            body: LightingFlashRequest(count: count),
            responseType: LightingState.self
        )
    }

    private func sendRequest<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        method: String,
        body: RequestBody,
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

            throw LightingServiceError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LightingServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(ResponseBody.self, from: data)
            } catch {
                throw LightingServiceError.decoding(error)
            }
        case 400:
            let message = (try? decoder.decode(LightingErrorDocument.self, from: data).error) ?? "bad request"
            throw LightingServiceError.invalidFlashCount(message: message)
        case 409:
            let message = (try? decoder.decode(LightingErrorDocument.self, from: data).error) ?? "conflict"
            if message == "flash_in_progress" {
                throw LightingServiceError.flashInProgress
            }

            throw LightingServiceError.server(statusCode: 409, message: message)
        default:
            let message = (try? decoder.decode(LightingErrorDocument.self, from: data).error) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw LightingServiceError.server(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func makeRequest<RequestBody: Encodable>(
        path: String,
        method: String,
        body: RequestBody
    ) throws -> URLRequest {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
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

extension LightingService: LightingServicing {}

enum LightingServiceError: Error {
    case invalidBaseURL(String)
    case invalidResponse
    case transport(Error)
    case decoding(Error)
    case invalidFlashCount(message: String)
    case flashInProgress
    case server(statusCode: Int, message: String)
}
