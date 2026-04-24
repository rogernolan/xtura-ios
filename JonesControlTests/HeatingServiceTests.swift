import Foundation
import Testing
@testable import JonesControl

@MainActor
struct HeatingServiceTests {
    @Test func scheduleDocumentAndRuntimeModeDecodeAndEncode() throws {
        let documentData = Data(
            """
            {
              "timezone": "Europe/London",
              "programs": [
                {
                  "id": "everyday-default",
                  "enabled": true,
                  "days": ["mon", "tue", "wed", "thu", "fri", "sat", "sun"],
                  "periods": [
                    { "start": "00:00", "mode": "off" },
                    { "start": "05:30", "mode": "heat", "target_celsius": 20.0 },
                    { "start": "08:00", "mode": "off" }
                  ]
                }
              ],
              "revision": "2026-04-22T09:31:45.123456Z"
            }
            """.utf8
        )
        let modeData = Data(
            """
            {
              "mode": "boost",
              "boost": {
                "target_celsius": 22.0,
                "expires_at": "2026-04-22T11:20:00Z",
                "resume_mode": "manual",
                "resume_manual_target_celsius": 19.0
              },
              "updated_at": "2026-04-22T10:20:00Z"
            }
            """.utf8
        )

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let document = try decoder.decode(HeatingScheduleDocument.self, from: documentData)
        let mode = try decoder.decode(HeatingRuntimeModeDocument.self, from: modeData)

        #expect(document.programs[0].periods[1].targetCelsius == 20)
        #expect(mode.boost?.resumeMode == .manual)
        #expect(mode.boost?.resumeManualTargetCelsius == 19)

        let encodedDocument = try encoder.encode(document)
        let encodedMode = try encoder.encode(mode)

        let roundTrippedDocument = try decoder.decode(HeatingScheduleDocument.self, from: encodedDocument)
        let roundTrippedMode = try decoder.decode(HeatingRuntimeModeDocument.self, from: encodedMode)

        #expect(roundTrippedDocument == document)
        #expect(roundTrippedMode == mode)
    }

    @Test func serviceSurfacesConflictResponsesDistinctly() async throws {
        let session = makeSession(protocolClass: HeatingServiceConflictURLProtocol.self)
        let service = try HeatingService(baseURLString: "http://example.com", session: session)

        do {
            _ = try await service.fetchHeatingSchedule()
            Issue.record("Expected conflict response.")
        } catch let error as HeatingServiceError {
            guard case .conflict(let message) = error else {
                Issue.record("Expected conflict error, got \(error).")
                return
            }

            #expect(message == "schedule revision conflict")
        }
    }

    @Test func serviceSurfacesValidationFailuresDistinctly() async throws {
        let session = makeSession(protocolClass: HeatingServiceValidationURLProtocol.self)
        let service = try HeatingService(baseURLString: "http://example.com", session: session)

        do {
            _ = try await service.fetchHeatingSchedule()
            Issue.record("Expected validation failure response.")
        } catch let error as HeatingServiceError {
            guard case .validationFailed(let messages) = error else {
                Issue.record("Expected validation failure, got \(error).")
                return
            }

            #expect(messages == ["automation.heating_programs[0]: heat periods must set target_celsius"])
        }
    }

    @Test func serviceTreatsNetworkingIssuesAsTransportErrors() async throws {
        let session = makeSession(protocolClass: HeatingServiceTransportURLProtocol.self)
        let service = try HeatingService(baseURLString: "http://example.com", session: session)

        do {
            _ = try await service.fetchHeatingSchedule()
            Issue.record("Expected transport failure.")
        } catch let error as HeatingServiceError {
            guard case .transport(let underlying) = error else {
                Issue.record("Expected transport error, got \(error).")
                return
            }

            let urlError = underlying as? URLError
            #expect(urlError?.code == .cannotConnectToHost)
        }
    }

    private func makeSession(protocolClass: URLProtocol.Type) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        return URLSession(configuration: configuration)
    }
}

private class FixedResponseURLProtocol: URLProtocol {
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

    func fail(with error: Error) {
        client?.urlProtocol(self, didFailWithError: error)
    }
}

private final class HeatingServiceConflictURLProtocol: FixedResponseURLProtocol {
    override func startLoading() {
        send(statusCode: 409, data: Data(#"{"error":"schedule revision conflict"}"#.utf8))
    }
}

private final class HeatingServiceValidationURLProtocol: FixedResponseURLProtocol {
    override func startLoading() {
        send(
            statusCode: 400,
            data: Data(
                """
                {
                  "error": "validation_failed",
                  "details": [
                    { "message": "automation.heating_programs[0]: heat periods must set target_celsius" }
                  ]
                }
                """.utf8
            )
        )
    }
}

private final class HeatingServiceTransportURLProtocol: FixedResponseURLProtocol {
    override func startLoading() {
        fail(with: URLError(.cannotConnectToHost))
    }
}
