# JonesControl Tailscale Launch Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app check reachability for the router page whenever it launches or returns to the foreground, assume Tailscale VPN On Demand handles connection, and automatically show the router UI in-app once the page becomes reachable.

**Architecture:** Replace the starter-template SwiftData list UI with a small launch coordinator that reacts to scene lifecycle changes, runs a retrying reachability probe against `http://192.168.1.1:8888`, and transitions between loading, failure, and loaded-web-page states. Keep the VPN behavior out of app-owned networking APIs; the app only depends on Tailscale VPN On Demand being configured externally.

**Tech Stack:** SwiftUI, WebKit, URLSession, XCTest/Swift Testing, iOS scene phase APIs

---

## File Structure

- Modify: `JonesControl/JonesControlApp.swift`
  - Remove the unused SwiftData container setup and inject the new launch coordinator at the app root.
- Modify: `JonesControl/ContentView.swift`
  - Replace the starter list UI with a state-driven shell that shows connecting, failure, or the embedded router page.
- Create: `JonesControl/AppLaunchModel.swift`
  - Observable state owner for launch/foreground refresh behavior, probe orchestration, and UI state transitions.
- Create: `JonesControl/RouterReachabilityService.swift`
  - Small service that polls the router page URL with a long timeout and bounded retries.
- Create: `JonesControl/RouterWebView.swift`
  - `UIViewRepresentable` wrapper around `WKWebView` for displaying `http://192.168.1.1:8888` in-app.
- Delete: `JonesControl/Item.swift`
  - Starter template model is no longer used.
- Create: `JonesControlTests/AppLaunchModelTests.swift`
  - Unit tests for state transitions and retry behavior using a fake reachability service.

---

### Task 1: Replace the Template App Shell

**Files:**
- Modify: `JonesControl/JonesControlApp.swift`
- Modify: `JonesControl/ContentView.swift`
- Delete: `JonesControl/Item.swift`

- [ ] **Step 1: Write the failing UI-shell test**

```swift
import Testing
@testable import JonesControl

struct AppLaunchModelTests {
    @Test func initialStateShowsConnectingMessage() async throws {
        let model = AppLaunchModel(
            reachabilityService: StubRouterReachabilityService(result: .failure(AppLaunchError.unreachable)),
            targetURL: URL(string: "http://192.168.1.1:8888")!
        )

        #expect(model.viewState == .checkingConnection)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JonesControlTests/AppLaunchModelTests`

Expected: FAIL because `AppLaunchModel`, `StubRouterReachabilityService`, and `AppLaunchError` do not exist yet.

- [ ] **Step 3: Write minimal app shell implementation**

`JonesControl/JonesControlApp.swift`

```swift
import SwiftUI

@main
struct JonesControlApp: App {
    @State private var appLaunchModel = AppLaunchModel.live()

    var body: some Scene {
        WindowGroup {
            ContentView(model: appLaunchModel)
        }
    }
}
```

`JonesControl/ContentView.swift`

```swift
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppLaunchModel

    var body: some View {
        Group {
            switch model.viewState {
            case .checkingConnection:
                ProgressView("Checking Tailscale connection...")
            case .failed(let message):
                VStack(spacing: 16) {
                    Text("Router page unavailable")
                    Text(message)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await model.refresh() }
                    }
                }
                .padding()
            case .loaded(let url):
                RouterWebView(url: url)
            }
        }
    }
}
```

- [ ] **Step 4: Delete the unused template model**

Remove `JonesControl/Item.swift` entirely.

- [ ] **Step 5: Run test to verify it still fails for the right reason**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JonesControlTests/AppLaunchModelTests`

Expected: FAIL because `AppLaunchModel` and the reachability test helpers still do not exist, while the old SwiftData template errors are gone.

- [ ] **Step 6: Commit**

```bash
git add JonesControl/JonesControlApp.swift JonesControl/ContentView.swift JonesControl/Item.swift JonesControlTests/AppLaunchModelTests.swift
git commit -m "refactor: replace starter template shell"
```

---

### Task 2: Add the Launch Coordinator and State Model

**Files:**
- Create: `JonesControl/AppLaunchModel.swift`
- Test: `JonesControlTests/AppLaunchModelTests.swift`

- [ ] **Step 1: Write the failing state-transition tests**

`JonesControlTests/AppLaunchModelTests.swift`

```swift
import Foundation
import Testing
@testable import JonesControl

struct AppLaunchModelTests {
    @Test func refreshLoadsRouterWhenReachabilitySucceeds() async throws {
        let model = AppLaunchModel(
            reachabilityService: StubRouterReachabilityService(result: .success(())),
            targetURL: URL(string: "http://192.168.1.1:8888")!
        )

        await model.refresh()

        #expect(model.viewState == .loaded(URL(string: "http://192.168.1.1:8888")!))
    }

    @Test func refreshShowsFailureMessageWhenReachabilityFails() async throws {
        let model = AppLaunchModel(
            reachabilityService: StubRouterReachabilityService(result: .failure(AppLaunchError.unreachable)),
            targetURL: URL(string: "http://192.168.1.1:8888")!
        )

        await model.refresh()

        #expect(model.viewState == .failed("Waiting for Tailscale to connect to the router."))
    }
}

private struct StubRouterReachabilityService: RouterReachabilityServing {
    let result: Result<Void, Error>

    func waitUntilReachable(at _: URL) async throws {
        switch result {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JonesControlTests/AppLaunchModelTests/testRefreshLoadsRouterWhenReachabilitySucceeds -only-testing:JonesControlTests/AppLaunchModelTests/testRefreshShowsFailureMessageWhenReachabilityFails`

Expected: FAIL because `RouterReachabilityServing`, `AppLaunchModel`, and `AppLaunchError` are not defined.

- [ ] **Step 3: Write minimal coordinator implementation**

`JonesControl/AppLaunchModel.swift`

```swift
import Foundation
import Observation

enum AppLaunchViewState: Equatable {
    case checkingConnection
    case failed(String)
    case loaded(URL)
}

enum AppLaunchError: Error {
    case unreachable
}

protocol RouterReachabilityServing {
    func waitUntilReachable(at url: URL) async throws
}

@Observable
@MainActor
final class AppLaunchModel {
    var viewState: AppLaunchViewState = .checkingConnection

    private let reachabilityService: RouterReachabilityServing
    private let targetURL: URL

    init(reachabilityService: RouterReachabilityServing, targetURL: URL) {
        self.reachabilityService = reachabilityService
        self.targetURL = targetURL
    }

    static func live() -> AppLaunchModel {
        AppLaunchModel(
            reachabilityService: RouterReachabilityService(),
            targetURL: URL(string: "http://192.168.1.1:8888")!
        )
    }

    func refresh() async {
        viewState = .checkingConnection

        do {
            try await reachabilityService.waitUntilReachable(at: targetURL)
            viewState = .loaded(targetURL)
        } catch {
            viewState = .failed("Waiting for Tailscale to connect to the router.")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JonesControlTests/AppLaunchModelTests`

Expected: PASS for the two new tests.

- [ ] **Step 5: Commit**

```bash
git add JonesControl/AppLaunchModel.swift JonesControlTests/AppLaunchModelTests.swift
git commit -m "feat: add launch coordinator state model"
```

---

### Task 3: Trigger Refresh on Launch and Foreground

**Files:**
- Modify: `JonesControl/ContentView.swift`
- Test: `JonesControlTests/AppLaunchModelTests.swift`

- [ ] **Step 1: Write the failing lifecycle test**

Add this test:

```swift
@Test func refreshCountIncrementsWhenRefreshRuns() async throws {
    let model = AppLaunchModel(
        reachabilityService: StubRouterReachabilityService(result: .success(())),
        targetURL: URL(string: "http://192.168.1.1:8888")!
    )

    #expect(model.refreshCount == 0)
    await model.refresh()
    #expect(model.refreshCount == 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JonesControlTests/AppLaunchModelTests/testRefreshCountIncrementsWhenRefreshRuns`

Expected: FAIL because `refreshCount` does not exist.

- [ ] **Step 3: Add minimal lifecycle-tracking implementation**

Update `JonesControl/AppLaunchModel.swift`:

```swift
@Observable
@MainActor
final class AppLaunchModel {
    var viewState: AppLaunchViewState = .checkingConnection
    var refreshCount = 0

    // existing properties...

    func refresh() async {
        refreshCount += 1
        viewState = .checkingConnection

        do {
            try await reachabilityService.waitUntilReachable(at: targetURL)
            viewState = .loaded(targetURL)
        } catch {
            viewState = .failed("Waiting for Tailscale to connect to the router.")
        }
    }
}
```

Update `JonesControl/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppLaunchModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.viewState {
            case .checkingConnection:
                ProgressView("Checking Tailscale connection...")
            case .failed(let message):
                VStack(spacing: 16) {
                    Text("Router page unavailable")
                    Text(message)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await model.refresh() }
                    }
                }
                .padding()
            case .loaded(let url):
                RouterWebView(url: url)
            }
        }
        .task {
            await model.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await model.refresh() }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JonesControlTests/AppLaunchModelTests`

Expected: PASS, including the refresh-count test.

- [ ] **Step 5: Commit**

```bash
git add JonesControl/AppLaunchModel.swift JonesControl/ContentView.swift JonesControlTests/AppLaunchModelTests.swift
git commit -m "feat: refresh router flow on launch and foreground"
```

---

### Task 4: Add a Long-Timeout Reachability Probe

**Files:**
- Create: `JonesControl/RouterReachabilityService.swift`
- Modify: `JonesControl/AppLaunchModel.swift`
- Test: `JonesControlTests/AppLaunchModelTests.swift`

- [ ] **Step 1: Write the failing probe configuration test**

Add this test:

```swift
@Test func liveServiceUsesLongTimeoutConfiguration() async throws {
    let configuration = RouterReachabilityService.makeURLSessionConfiguration()

    #expect(configuration.timeoutIntervalForRequest == 30)
    #expect(configuration.timeoutIntervalForResource == 120)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JonesControlTests/AppLaunchModelTests/testLiveServiceUsesLongTimeoutConfiguration`

Expected: FAIL because `RouterReachabilityService` does not exist.

- [ ] **Step 3: Write minimal reachability service**

`JonesControl/RouterReachabilityService.swift`

```swift
import Foundation

struct RouterReachabilityService: RouterReachabilityServing {
    private let session: URLSession
    private let pollIntervalNanoseconds: UInt64
    private let maxAttempts: Int

    init(
        session: URLSession = URLSession(configuration: Self.makeURLSessionConfiguration()),
        pollIntervalNanoseconds: UInt64 = 3_000_000_000,
        maxAttempts: Int = 10
    ) {
        self.session = session
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.maxAttempts = maxAttempts
    }

    static func makeURLSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = true
        return configuration
    }

    func waitUntilReachable(at url: URL) async throws {
        for attempt in 1...maxAttempts {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData

            do {
                let (_, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, (200..<500).contains(httpResponse.statusCode) {
                    return
                }
            } catch {
                if attempt == maxAttempts {
                    throw AppLaunchError.unreachable
                }
            }

            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        throw AppLaunchError.unreachable
    }
}
```

- [ ] **Step 4: Wire the live service into the model**

Confirm `JonesControl/AppLaunchModel.swift` still uses:

```swift
static func live() -> AppLaunchModel {
    AppLaunchModel(
        reachabilityService: RouterReachabilityService(),
        targetURL: URL(string: "http://192.168.1.1:8888")!
    )
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JonesControlTests/AppLaunchModelTests`

Expected: PASS for the timeout configuration test and earlier coordinator tests.

- [ ] **Step 6: Commit**

```bash
git add JonesControl/RouterReachabilityService.swift JonesControl/AppLaunchModel.swift JonesControlTests/AppLaunchModelTests.swift
git commit -m "feat: add long-timeout router reachability probe"
```

---

### Task 5: Show the Router Page In-App

**Files:**
- Create: `JonesControl/RouterWebView.swift`
- Modify: `JonesControl/ContentView.swift`

- [ ] **Step 1: Write the failing build expectation**

Add this usage to `JonesControl/ContentView.swift` if it is not already present:

```swift
case .loaded(let url):
    RouterWebView(url: url)
```

Run the build before the file exists.

- [ ] **Step 2: Run build to verify it fails**

Run: `xcodebuild build -scheme JonesControl -destination 'generic/platform=iOS'`

Expected: FAIL because `RouterWebView` does not exist.

- [ ] **Step 3: Write minimal web view wrapper**

`JonesControl/RouterWebView.swift`

```swift
import SwiftUI
import WebKit

struct RouterWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context _: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        return WKWebView(frame: .zero, configuration: configuration)
    }

    func updateUIView(_ webView: WKWebView, context _: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
    }
}
```

- [ ] **Step 4: Run build to verify it passes**

Run: `xcodebuild build -scheme JonesControl -destination 'generic/platform=iOS'`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add JonesControl/RouterWebView.swift JonesControl/ContentView.swift
git commit -m "feat: embed router page in web view"
```

---

### Task 6: Verify the End-to-End Flow and Polish Failure Copy

**Files:**
- Modify: `JonesControl/ContentView.swift`
- Modify: `JonesControl/AppLaunchModel.swift`

- [ ] **Step 1: Write the failing UX expectation**

Update the failure expectation in `JonesControlTests/AppLaunchModelTests.swift`:

```swift
#expect(model.viewState == .failed("Open Tailscale and confirm VPN On Demand is allowed, then try again."))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JonesControlTests/AppLaunchModelTests/testRefreshShowsFailureMessageWhenReachabilityFails`

Expected: FAIL because the failure message still uses the older copy.

- [ ] **Step 3: Write minimal copy update**

Update `JonesControl/AppLaunchModel.swift`:

```swift
func refresh() async {
    refreshCount += 1
    viewState = .checkingConnection

    do {
        try await reachabilityService.waitUntilReachable(at: targetURL)
        viewState = .loaded(targetURL)
    } catch {
        viewState = .failed("Open Tailscale and confirm VPN On Demand is allowed, then try again.")
    }
}
```

Keep the retry button in `JonesControl/ContentView.swift`:

```swift
Button("Try Again") {
    Task { await model.refresh() }
}
```

- [ ] **Step 4: Run the focused test and then the full suite**

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:JonesControlTests/AppLaunchModelTests/testRefreshShowsFailureMessageWhenReachabilityFails`

Expected: PASS

Run: `xcodebuild test -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16'`

Expected: All tests PASS

- [ ] **Step 5: Run a manual simulator verification**

Run: `xcodebuild build -scheme JonesControl -destination 'platform=iOS Simulator,name=iPhone 16'`

Then launch in Simulator and verify:
- first launch shows the connecting state
- if the router page becomes reachable, the embedded web page loads automatically
- backgrounding and foregrounding re-runs the probe
- if the router page stays unavailable, the failure screen and retry button appear

- [ ] **Step 6: Commit**

```bash
git add JonesControl/AppLaunchModel.swift JonesControl/ContentView.swift JonesControlTests/AppLaunchModelTests.swift
git commit -m "polish: improve router connection fallback messaging"
```

---

## Later Follow-Up: Hybrid Recovery Flow

This is intentionally out of scope for the first implementation pass.

- Add a secondary recovery path after the initial on-demand timeout expires.
- Keep the current automatic probe as the default path.
- If the page still is not reachable, present a stronger recovery UI that can later include:
  - an explicit “Open Tailscale” action if we confirm a supported app handoff
  - troubleshooting steps for VPN On Demand state
  - a second-stage retry window after the user returns from Tailscale

When this becomes active work, write a separate implementation plan rather than expanding the first pass mid-flight.
