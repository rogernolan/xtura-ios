import Observation
import Foundation

@MainActor
@Observable
final class AppLaunchModel {
    enum LaunchState: Equatable {
        case idle
        case loading
        case loaded(url: URL)
        case refreshing(url: URL)
        case failure(message: String)
    }

    static let routerURL = routerReachabilityURL
    static let failureMessage = "JonesControl could not reach 192.168.1.1:8888 yet. Tailscale VPN On Demand may still be bringing the tunnel up, and we will keep retrying."

    var launchState: LaunchState = .idle

    @ObservationIgnored
    private let reachabilityService: any RouterReachabilityServicing

    init(reachabilityService: (any RouterReachabilityServicing)? = nil) {
        self.reachabilityService = reachabilityService ?? RouterReachabilityService()
    }

    var failureMessage: String {
        Self.failureMessage
    }

    func refresh() async {
        switch launchState {
        case .loading, .refreshing(_):
            return
        case .idle, .loaded(_), .failure(_):
            break
        }

        let previousState = launchState
        switch previousState {
        case .loaded(let url):
            launchState = .refreshing(url: url)
        case .idle, .failure:
            launchState = .loading
        case .loading, .refreshing:
            return
        }

        do {
            try await reachabilityService.probe()
            launchState = .loaded(url: Self.routerURL)
        } catch is CancellationError {
            switch previousState {
            case .refreshing(let url), .loaded(let url):
                launchState = .loaded(url: url)
            case .idle:
                launchState = .idle
            case .failure(_):
                launchState = .failure(message: Self.failureMessage)
            case .loading:
                launchState = .loading
            }
            return
        } catch {
            switch previousState {
            case .loaded(let url), .refreshing(let url):
                launchState = .loaded(url: url)
            case .idle, .loading:
                launchState = .failure(message: Self.failureMessage)
            case .failure(_):
                launchState = .failure(message: Self.failureMessage)
            }
        }
    }
}
