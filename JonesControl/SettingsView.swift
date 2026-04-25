import SwiftUI

struct SettingsView: View {
    @Bindable var settings: HeatingServiceSettings

    var body: some View {
        NavigationStack {
            Form {
                Section("Heating Service") {
                    TextField(HeatingServiceSettings.placeholder, text: $settings.baseURLText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textContentType(.URL)

                    if let configuredBaseURL = settings.configuredBaseURL {
                        LabeledContent("Saved URL") {
                            Text(configuredBaseURL.absoluteString)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    } else {
                        Text("Enter the full base URL for the heating service, including scheme and port.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("JonesControl uses this address for the heating schedule and mode APIs. A typical value looks like `\(HeatingServiceSettings.defaultBaseURL)`.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
