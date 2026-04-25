import Testing
import Foundation
@testable import JonesControl

@MainActor
struct AppLaunchModelTests {
    @Test func refreshLoadsSuccessfully() async throws {
        let service = ReachabilityServiceSpy(result: .success)
        let model = AppLaunchModel(reachabilityService: service)

        #expect(model.launchState == .idle)

        await model.refresh()

        #expect(service.probeCallCount == 1)
        #expect(model.launchState == .loaded(url: AppLaunchModel.routerURL))
    }

    @Test func refreshShowsFailureWhenReachabilityFails() async throws {
        let service = ReachabilityServiceSpy(result: .failure(TestError.unreachable))
        let model = AppLaunchModel(reachabilityService: service)

        await model.refresh()

        #expect(service.probeCallCount == 1)
        #expect(model.launchState == .failure(message: model.failureMessage))
        #expect(model.failureMessage.contains("Tailscale VPN On Demand"))
    }

    @Test func refreshDoesNotConvertCancellationIntoFailure() async throws {
        let service = CancellationThenSuccessReachabilityService()
        let model = AppLaunchModel(reachabilityService: service)

        let refreshTask = Task { await model.refresh() }
        await Task.yield()

        #expect(model.launchState == .loading)

        refreshTask.cancel()
        await refreshTask.value

        #expect(service.probeCallCount == 1)
        #expect(model.launchState == .idle)

        await model.refresh()

        #expect(service.probeCallCount == 2)
        #expect(model.launchState == .loaded(url: AppLaunchModel.routerURL))
    }

    @Test func refreshFromLoadedKeepsTheRouterVisibleWhileRefreshing() async throws {
        let service = CancellationThenSuccessReachabilityService()
        let model = AppLaunchModel(reachabilityService: service)
        model.launchState = .loaded(url: AppLaunchModel.routerURL)

        let refreshTask = Task { await model.refresh() }
        await Task.yield()

        #expect(model.launchState == .refreshing(url: AppLaunchModel.routerURL))

        refreshTask.cancel()
        await refreshTask.value

        #expect(service.probeCallCount == 1)
        #expect(model.launchState == .loaded(url: AppLaunchModel.routerURL))
    }

    @Test func reachabilityServiceRetriesAfterAnInitialFailure() async throws {
        RetryStubURLProtocol.requestCount = 0
        RetryStubURLProtocol.responses = [
            .failure(URLError(.timedOut)),
            .success(statusCode: 200, data: Data())
        ]

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RetryStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = RouterReachabilityService(
            session: session,
            maximumAttempts: 3,
            retryDelayNanoseconds: 0
        )

        try await service.probe()

        #expect(RetryStubURLProtocol.requestCount == 2)
    }

    @Test func reachabilityServiceNormalizesNSURLSessionCancellation() async throws {
        CancellationStubURLProtocol.requestCount = 0
        CancellationStubURLProtocol.responses = [
            .failure(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        ]

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CancellationStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = RouterReachabilityService(
            session: session,
            maximumAttempts: 3,
            retryDelayNanoseconds: 0
        )

        var threwCancellation = false
        do {
            try await service.probe()
        } catch is CancellationError {
            threwCancellation = true
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(threwCancellation)
        #expect(CancellationStubURLProtocol.requestCount == 1)
    }

    @Test func routerWebViewOnlyLoadsWhenTheURLChanges() throws {
        let url = AppLaunchModel.routerURL
        let coordinator = RouterWebView.Coordinator()

        #expect(coordinator.shouldLoad(desiredURL: url))

        coordinator.markLoadStarted(url)
        #expect(coordinator.shouldLoad(desiredURL: url) == false)

        coordinator.markLoadFailed()
        #expect(coordinator.shouldLoad(desiredURL: url))

        coordinator.markLoadStarted(url)
        coordinator.markLoadCommitted(url)
        #expect(coordinator.shouldLoad(desiredURL: url) == false)

        let redirectedURL = URL(string: "http://192.168.1.1:8888/status")!
        #expect(coordinator.shouldLoad(desiredURL: redirectedURL))
    }
}

private enum TestError: Error {
    case unreachable
}

private final class ReachabilityServiceSpy: RouterReachabilityServicing {
    enum Result {
        case success
        case failure(Error)
    }

    private(set) var probeCallCount = 0
    let result: Result

    init(result: Result) {
        self.result = result
    }

    func probe() async throws {
        probeCallCount += 1
        switch result {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

private final class CancellationThenSuccessReachabilityService: RouterReachabilityServicing {
    private(set) var probeCallCount = 0
    private var shouldSuspend = true

    func probe() async throws {
        probeCallCount += 1
        if shouldSuspend {
            shouldSuspend = false
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

private final class RetryStubURLProtocol: URLProtocol {
    struct Response {
        let result: Result<(statusCode: Int, data: Data), Error>
    }

    static var responses: [Response] = []
    static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1

        guard !Self.responses.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = Self.responses.removeFirst()
        switch response.result {
        case .success(let payload):
            let httpResponse = HTTPURLResponse(
                url: request.url ?? URL(string: "http://127.0.0.1")!,
                statusCode: payload.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: payload.data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class CancellationStubURLProtocol: URLProtocol {
    struct Response {
        let result: Result<(statusCode: Int, data: Data), Error>
    }

    static var responses: [Response] = []
    static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1

        guard !Self.responses.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = Self.responses.removeFirst()
        switch response.result {
        case .success(let payload):
            let httpResponse = HTTPURLResponse(
                url: request.url ?? URL(string: "http://127.0.0.1")!,
                statusCode: payload.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: payload.data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension RetryStubURLProtocol.Response {
    static func success(statusCode: Int, data: Data) -> Self {
        Self(result: .success((statusCode: statusCode, data: data)))
    }

    static func failure(_ error: Error) -> Self {
        Self(result: .failure(error))
    }
}

private extension CancellationStubURLProtocol.Response {
    static func success(statusCode: Int, data: Data) -> Self {
        Self(result: .success((statusCode: statusCode, data: data)))
    }

    static func failure(_ error: Error) -> Self {
        Self(result: .failure(error))
    }
}
