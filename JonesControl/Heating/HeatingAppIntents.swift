import AppIntents
import Foundation

struct BoostJonesHeatingIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Boost Heating"
    nonisolated static let description = IntentDescription("Boosts the heating to 21°C for one hour.")

    nonisolated static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try await BoostJonesHeatingIntentAction().perform()
            return .result(dialog: "Heating boosted to 21 degrees for one hour.")
        } catch let error as HeatingFeatureModelError {
            let message = await MainActor.run {
                HeatingFeatureModel.message(for: error)
            }
            throw HeatingIntentError(message: message)
        } catch {
            throw HeatingIntentError(message: error.localizedDescription)
        }
    }
}

struct BoostJonesHeatingIntentAction {
    nonisolated static let targetCelsius = HeatingFeatureModel.defaultBoostTargetCelsius
    nonisolated static let durationMinutes = HeatingFeatureModel.defaultBoostDurationMinutes

    private let boostHeating: @MainActor (Double, Int) async throws -> Void

    init(boostHeating: @escaping @MainActor (Double, Int) async throws -> Void = { targetCelsius, durationMinutes in
        let model = HeatingFeatureModel()
        try await model.setRuntimeModeBoost(
            targetCelsius: targetCelsius,
            durationMinutes: durationMinutes
        )
    }) {
        self.boostHeating = boostHeating
    }

    @MainActor
    func perform() async throws {
        try await boostHeating(Self.targetCelsius, Self.durationMinutes)
    }
}

private struct HeatingIntentError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
