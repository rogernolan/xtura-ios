import Testing
@testable import JonesControl

@MainActor
struct HeatingAppIntentTests {
    @Test func boostJonesHeatingIntentActionUsesDefaultBoostSettings() async throws {
        var receivedTargetCelsius: Double?
        var receivedDurationMinutes: Int?

        let action = BoostJonesHeatingIntentAction { targetCelsius, durationMinutes in
            receivedTargetCelsius = targetCelsius
            receivedDurationMinutes = durationMinutes
        }

        try await action.perform()

        #expect(receivedTargetCelsius == 21)
        #expect(receivedDurationMinutes == 60)
    }
}
