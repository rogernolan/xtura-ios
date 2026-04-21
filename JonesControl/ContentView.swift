import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var launchModel = AppLaunchModel()

    var body: some View {
        LaunchStateView(
            launchState: launchModel.launchState,
            retryAction: retry
        )
        .task {
            await launchModel.refresh()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                return
            }

            await launchModel.refresh()
        }
    }

    private func retry() {
        Task {
            await launchModel.refresh()
        }
    }
}

private struct LaunchStateView: View {
    let launchState: AppLaunchModel.LaunchState
    let retryAction: () -> Void

    var body: some View {
        switch launchState {
        case .idle, .loading:
            ProgressView("Checking Tailscale VPN On Demand and router reachability...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
        case .loaded(let url):
            RouterContentView(url: url, isRefreshing: false)
        case .refreshing(let url):
            RouterContentView(url: url, isRefreshing: true)
        case .failure(let message):
            failureView(message: message)
        }
    }

    private func failureView(message: String) -> some View {
        VStack(spacing: 12) {
            Text("Connection needs attention")
                .font(.title2.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry", action: retryAction)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct RouterContentView: View {
    let url: URL
    let isRefreshing: Bool

    var body: some View {
        ZStack(alignment: .top) {
            RouterWebView(url: url)
                .ignoresSafeArea()

            if isRefreshing {
                ProgressView("Refreshing connection...")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 16)
            }
        }
    }
}

#Preview("Loading") {
    LaunchStateView(launchState: .loading, retryAction: {})
}

#Preview("Loaded") {
    LaunchStateView(
        launchState: .loaded(url: AppLaunchModel.routerURL),
        retryAction: {}
    )
}

#Preview("Failure") {
    LaunchStateView(
        launchState: .failure(message: AppLaunchModel.failureMessage),
        retryAction: {}
    )
}
