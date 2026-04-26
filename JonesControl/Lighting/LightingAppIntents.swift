import AppIntents
import Foundation

struct FlashOutsideLightsIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Flash Outside Lights"
    nonisolated static let description = IntentDescription("Flashes the outside lights three times.")

    nonisolated static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try await flashOutsideLights()
            return .result(dialog: "Outside lights flashed three times.")
        } catch let error as LightingFeatureModelError {
            throw LightingIntentError(message: LightingFeatureModel.message(for: error))
        } catch {
            throw LightingIntentError(message: error.localizedDescription)
        }
    }

    @MainActor
    private func flashOutsideLights() async throws {
        let model = LightingFeatureModel()
        try await model.flashExternalLights(count: 3)
    }
}

struct JonesControlShortcuts: AppShortcutsProvider {
    nonisolated static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FlashOutsideLightsIntent(),
            phrases: [
                "Flash the lights in \(.applicationName)",
                "Flash the outside lights in \(.applicationName)",
                "Flash \(.applicationName) outside lights"
            ],
            shortTitle: "Flash Lights",
            systemImageName: "lightbulb.2"
        )
    }
}

private struct LightingIntentError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
