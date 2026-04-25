import SwiftUI

struct LightingView: View {
    @Environment(HeatingServiceSettings.self) private var serviceSettings
    @State private var model = LightingFeatureModel()
    @State private var flashCount = LightingFeatureModel.minimumFlashCount
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("External Lights") {
                    Stepper(
                        value: $flashCount,
                        in: LightingFeatureModel.validFlashCountRange
                    ) {
                        LabeledContent("Count") {
                            TextField("Count", value: $flashCount, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(width: 56)
                                .accessibilityIdentifier("lighting.flash.count")
                        }
                    }
                    .disabled(model.isFlashing)

                    Button {
                        Task { @MainActor in
                            await flashExternalLights()
                        }
                    } label: {
                        if model.isFlashing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Flashing")
                            }
                        } else {
                            Text("Flash")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isFlashing || !LightingFeatureModel.validFlashCountRange.contains(flashCount))
                    .accessibilityIdentifier("lighting.flash.button")

                    if let lastFlashMessage = model.lastFlashMessage {
                        Text(lastFlashMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let lastState = model.lastState {
                        LabeledContent("External lights") {
                            Text(externalLightsStateText(lastState))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if serviceSettings.configuredBaseURL == nil {
                    Section {
                        Text("Set the service URL in Settings before flashing external lights.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Lighting")
        }
        .onChange(of: flashCount, initial: false) { _, newValue in
            flashCount = min(
                LightingFeatureModel.maximumFlashCount,
                max(LightingFeatureModel.minimumFlashCount, newValue)
            )
        }
        .alert("Lighting", isPresented: alertMessageIsPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var alertMessageIsPresented: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    alertMessage = nil
                }
            }
        )
    }

    private func flashExternalLights() async {
        do {
            try await model.flashExternalLights(count: flashCount)
        } catch let error as LightingFeatureModelError {
            alertMessage = LightingFeatureModel.message(for: error)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func externalLightsStateText(_ state: LightingState) -> String {
        guard state.externalKnown else {
            return "Unknown"
        }

        return state.externalOn ? "On" : "Off"
    }
}

#Preview {
    LightingView()
        .environment(HeatingServiceSettings())
}
