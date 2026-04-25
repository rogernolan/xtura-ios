import Foundation
import Testing
@testable import JonesControl

@MainActor
struct LightingFeatureModelTests {
    @Test func flashRequiresConfiguredBaseURL() async throws {
        let model = LightingFeatureModel(baseURLProvider: { nil })

        do {
            try await model.flashExternalLights(count: 1)
            Issue.record("Expected not configured error.")
        } catch let error as LightingFeatureModelError {
            #expect(error == .notConfigured)
        }

        #expect(model.lastState == nil)
        #expect(model.isFlashing == false)
    }

    @Test func flashRejectsCountsOutsideOneThroughFiveBeforeCallingService() async throws {
        let service = LightingServiceStub()
        let model = LightingFeatureModel(
            baseURLProvider: { URL(string: "http://example.com") },
            makeService: { _ in service }
        )

        do {
            try await model.flashExternalLights(count: 6)
            Issue.record("Expected invalid count error.")
        } catch let error as LightingFeatureModelError {
            #expect(error == .invalidFlashCount)
        }

        #expect(service.flashExternalLightsCallCount == 0)
        #expect(model.isFlashing == false)
    }

    @Test func flashUpdatesLastStateFromService() async throws {
        let service = LightingServiceStub(
            flashExternalLights: { count in
                #expect(count == 4)
                return LightingState(
                    externalKnown: true,
                    externalOn: true,
                    flashInProgress: false,
                    lastCommandError: nil,
                    lastUpdatedAt: "2026-04-25T10:10:00Z"
                )
            }
        )
        let model = LightingFeatureModel(
            baseURLProvider: { URL(string: "http://example.com") },
            makeService: { _ in service }
        )

        try await model.flashExternalLights(count: 4)

        #expect(service.flashExternalLightsCallCount == 1)
        #expect(model.lastState?.externalOn == true)
        #expect(model.lastFlashMessage == "External lights flashed 4 times.")
        #expect(model.isFlashing == false)
    }

    @Test func flashInProgressErrorsHaveFriendlyMessage() async throws {
        let model = LightingFeatureModel(
            baseURLProvider: { URL(string: "http://example.com") },
            makeService: { _ in
                LightingServiceStub(
                    flashExternalLights: { _ in
                        throw LightingServiceError.flashInProgress
                    }
                )
            }
        )

        do {
            try await model.flashExternalLights(count: 2)
            Issue.record("Expected flash in progress error.")
        } catch let error as LightingFeatureModelError {
            #expect(LightingFeatureModel.message(for: error) == "The external lights are already flashing.")
        }

        #expect(model.isFlashing == false)
    }
}

private final class LightingServiceStub: LightingServicing {
    var flashExternalLightsHandler: (Int) async throws -> LightingState

    private(set) var flashExternalLightsCallCount = 0

    init(
        flashExternalLights: @escaping (Int) async throws -> LightingState = { _ in
            LightingState(
                externalKnown: true,
                externalOn: false,
                flashInProgress: false,
                lastCommandError: nil,
                lastUpdatedAt: nil
            )
        }
    ) {
        self.flashExternalLightsHandler = flashExternalLights
    }

    func flashExternalLights(count: Int) async throws -> LightingState {
        flashExternalLightsCallCount += 1
        return try await flashExternalLightsHandler(count)
    }
}
