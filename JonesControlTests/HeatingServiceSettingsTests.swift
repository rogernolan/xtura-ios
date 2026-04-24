import Foundation
import Testing
@testable import JonesControl

@MainActor
struct HeatingServiceSettingsTests {
    @Test func loadsPersistedBaseURL() {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        userDefaults.set("http://vanpi.tail1234.ts.net:8080", forKey: HeatingServiceSettings.baseURLKey)

        let settings = HeatingServiceSettings(userDefaults: userDefaults)

        #expect(settings.baseURLText == "http://vanpi.tail1234.ts.net:8080")
        #expect(settings.configuredBaseURL?.absoluteString == "http://vanpi.tail1234.ts.net:8080")
    }

    @Test func persistsBaseURLChanges() {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)
        let settings = HeatingServiceSettings(userDefaults: userDefaults)

        settings.baseURLText = "https://heater.example.com:8443"

        #expect(userDefaults.string(forKey: HeatingServiceSettings.baseURLKey) == "https://heater.example.com:8443")
    }

    @Test func rejectsInvalidBaseURL() {
        #expect(URL.normalizedHeatingServiceBaseURL(from: "heater.local:8080") == nil)
        #expect(URL.normalizedHeatingServiceBaseURL(from: "ftp://heater.local:8080") == nil)
        #expect(URL.normalizedHeatingServiceBaseURL(from: "http://") == nil)
    }

    @Test func trimsWhitespaceAndTrailingSlash() {
        let url = URL.normalizedHeatingServiceBaseURL(from: "  http://heater.local:8080/ \n")

        #expect(url?.absoluteString == "http://heater.local:8080")
    }
}
