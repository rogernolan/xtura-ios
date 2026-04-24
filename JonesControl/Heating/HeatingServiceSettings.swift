import Foundation
import Observation

@MainActor
@Observable
final class HeatingServiceSettings {
    static let baseURLKey = "heatingServiceBaseURL"
    static let placeholder = "http://vanpi.tail1234.ts.net:8080"

    var baseURLText: String {
        didSet {
            userDefaults.set(baseURLText, forKey: Self.baseURLKey)
        }
    }

    @ObservationIgnored
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.baseURLText = userDefaults.string(forKey: Self.baseURLKey) ?? ""
    }

    var trimmedBaseURLText: String {
        baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var configuredBaseURL: URL? {
        URL.normalizedHeatingServiceBaseURL(from: trimmedBaseURLText)
    }

    var isConfigured: Bool {
        configuredBaseURL != nil
    }
}

extension URL {
    static func normalizedHeatingServiceBaseURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        guard var components = URLComponents(string: trimmed) else {
            return nil
        }

        guard let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }

        guard components.host?.isEmpty == false else {
            return nil
        }

        if components.path == "/" {
            components.path = ""
        }

        return components.url
    }
}
