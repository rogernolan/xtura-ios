import Foundation

let routerReachabilityURL = URL(string: "http://192.168.1.1:8888")!

protocol RouterReachabilityServicing {
    func probe() async throws
}

struct RouterReachabilityService: RouterReachabilityServicing {
    private let session: URLSession
    private let url: URL
    private let maximumAttempts: Int
    private let retryDelayNanoseconds: UInt64

    init(
        session: URLSession = Self.makeSession(),
        url: URL = routerReachabilityURL,
        maximumAttempts: Int = 3,
        retryDelayNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.session = session
        self.url = url
        self.maximumAttempts = maximumAttempts
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

    func probe() async throws {
        var lastError: Error?

        for attempt in 1...maximumAttempts {
            do {
                try await probeOnce()
                return
            } catch {
                if isCancellation(error) {
                    throw CancellationError()
                }

                lastError = error
                if attempt < maximumAttempts {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds)
                }
            }
        }

        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private func probeOnce() async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60

        let (data, response) = try await session.data(for: request)
        _ = data

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<400).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
