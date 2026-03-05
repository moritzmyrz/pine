import SwiftUI
import WebKit

struct WebViewContainer: NSViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel
    let tabID: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, tabID: tabID)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = viewModel.webView(for: tabID)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.navigationDelegate = context.coordinator
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let viewModel: BrowserViewModel
        private let tabID: UUID

        init(viewModel: BrowserViewModel, tabID: UUID) {
            self.viewModel = viewModel
            self.tabID = tabID
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            viewModel.syncTabState(from: webView, for: tabID)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            viewModel.syncTabState(from: webView, for: tabID)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModel.syncTabState(from: webView, for: tabID)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            viewModel.syncTabState(from: webView, for: tabID)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            viewModel.syncTabState(from: webView, for: tabID)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.targetFrame == nil {
                viewModel.openInNewTab(request: navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
