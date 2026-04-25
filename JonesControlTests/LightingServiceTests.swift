import Foundation
import Testing
@testable import JonesControl

@MainActor
struct LightingServiceTests {
    @Test func serviceSendsFlashCountInRequestBody() async throws {
        let protocolClass = LightingFlashURLProtocol.self
        protocolClass.reset()

        let session = makeSession(protocolClass: protocolClass)
        let service = try LightingService(baseURLString: "http://example.com", session: session)

        let state = try await service.flashExternalLights(count: 3)

        #expect(state.externalKnown == true)
        #expect(state.externalOn == false)
        #expect(state.flashInProgress == false)
        #expect(protocolClass.lastRequest?.httpMethod == "POST")
        #expect(protocolClass.lastRequest?.url?.path == "/v1/lights/external/flash")

        let request = try #require(protocolClass.lastRequest)
        let requestData = try #require(request.bodyData)
        let body = try JSONDecoder().decode(LightingFlashRequest.self, from: requestData)
        #expect(body.count == 3)
    }

    @Test func serviceSurfacesFlashInProgressConflictDistinctly() async throws {
        let session = makeSession(protocolClass: LightingConflictURLProtocol.self)
        let service = try LightingService(baseURLString: "http://example.com", session: session)

        do {
            _ = try await service.flashExternalLights(count: 2)
            Issue.record("Expected flash in progress response.")
        } catch let error as LightingServiceError {
            guard case .flashInProgress = error else {
                Issue.record("Expected flash in progress error, got \(error).")
                return
            }
        }
    }

    @Test func serviceSurfacesInvalidCountResponsesDistinctly() async throws {
        let session = makeSession(protocolClass: LightingInvalidCountURLProtocol.self)
        let service = try LightingService(baseURLString: "http://example.com", session: session)

        do {
            _ = try await service.flashExternalLights(count: 0)
            Issue.record("Expected invalid count response.")
        } catch let error as LightingServiceError {
            guard case .invalidFlashCount(let message) = error else {
                Issue.record("Expected invalid flash count error, got \(error).")
                return
            }

            #expect(message == "invalid flash count")
        }
    }

    private func makeSession(protocolClass: URLProtocol.Type) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        return URLSession(configuration: configuration)
    }
}

private extension URLRequest {
    var bodyData: Data? {
        if let httpBody {
            return httpBody
        }

        guard let stream = httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            guard count > 0 else {
                break
            }

            data.append(buffer, count: count)
        }

        return data.isEmpty ? nil : data
    }
}

private class LightingFixedResponseURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        fatalError("Subclasses must override startLoading().")
    }

    override func stopLoading() {}

    func send(statusCode: Int, data: Data) {
        let httpResponse = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class LightingFlashURLProtocol: LightingFixedResponseURLProtocol {
    static var lastRequest: URLRequest?

    static func reset() {
        lastRequest = nil
    }

    override func startLoading() {
        Self.lastRequest = request
        send(
            statusCode: 200,
            data: Data(
                """
                {
                  "external_known": true,
                  "external_on": false,
                  "flash_in_progress": false,
                  "last_updated_at": "2026-04-25T10:10:00Z"
                }
                """.utf8
            )
        )
    }
}

private final class LightingConflictURLProtocol: LightingFixedResponseURLProtocol {
    override func startLoading() {
        send(statusCode: 409, data: Data(#"{"error":"flash_in_progress"}"#.utf8))
    }
}

private final class LightingInvalidCountURLProtocol: LightingFixedResponseURLProtocol {
    override func startLoading() {
        send(statusCode: 400, data: Data(#"{"error":"invalid flash count"}"#.utf8))
    }
}
