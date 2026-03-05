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
        webView.uiDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.navigationDelegate = context.coordinator
        nsView.uiDelegate = context.coordinator
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
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
            viewModel.recordHistoryForCompletedNavigation(tabID: tabID)
            viewModel.refreshFavicon(for: tabID, from: webView)
            viewModel.applyStoredPageSettings(for: tabID, in: webView)
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
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }

            if navigationAction.targetFrame == nil {
                viewModel.openInNewTab(request: navigationAction.request, fromTabID: tabID)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if !navigationResponse.canShowMIMEType {
                decisionHandler(.download)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            let suggestedFilename = navigationAction.request.url?.lastPathComponent ?? "download"
            viewModel.downloadManager.track(download: download, suggestedFilename: suggestedFilename)
            download.delegate = self
        }

        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            let suggestedFilename = navigationResponse.response.suggestedFilename ?? "download"
            viewModel.downloadManager.track(download: download, suggestedFilename: suggestedFilename)
            download.delegate = self
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            viewModel.downloadManager.chooseDestination(suggestedFilename: suggestedFilename) { destination in
                self.viewModel.downloadManager.didChooseDestination(for: download, destination: destination)
                completionHandler(destination)
            }
        }

        func downloadDidFinish(_ download: WKDownload) {
            viewModel.downloadManager.didFinish(download: download)
        }

        func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
            viewModel.downloadManager.didFail(download: download, error: error)
        }
    }
}
