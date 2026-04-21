import SwiftUI
import WebKit

struct RouterWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.shouldLoad(desiredURL: url) else {
            return
        }

        context.coordinator.markLoadStarted(url)
        uiView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private(set) var committedURL: URL?
        private(set) var pendingURL: URL?

        func shouldLoad(desiredURL: URL) -> Bool {
            pendingURL != desiredURL && committedURL != desiredURL
        }

        func markLoadStarted(_ url: URL) {
            pendingURL = url
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            markLoadCommitted(webView.url ?? pendingURL)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            markLoadFailed()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            markLoadFailed()
        }

        func markLoadCommitted(_ url: URL?) {
            committedURL = url
            pendingURL = nil
        }

        func markLoadFailed() {
            pendingURL = nil
        }
    }
}
