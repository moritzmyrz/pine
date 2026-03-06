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
                let popupHost = navigationAction.request.url?.host?.lowercased()
                viewModel.shouldAllowPermissionRequest(type: .popups, host: popupHost) { [weak self] allowPopup in
                    guard let self else {
                        decisionHandler(.cancel)
                        return
                    }
                    if allowPopup {
                        self.viewModel.openInNewTab(request: navigationAction.request, fromTabID: self.tabID)
                    }
                    decisionHandler(.cancel)
                }
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
            viewModel.downloadManager.track(
                download: download,
                webView: webView,
                suggestedFilename: suggestedFilename,
                sourceURL: navigationAction.request.url
            )
            download.delegate = self
        }

        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            let suggestedFilename = navigationResponse.response.suggestedFilename ?? "download"
            viewModel.downloadManager.track(
                download: download,
                webView: webView,
                suggestedFilename: suggestedFilename,
                sourceURL: navigationResponse.response.url
            )
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
            viewModel.downloadManager.didFail(download: download, error: error, resumeData: resumeData)
        }

        @available(macOS 12.0, *)
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            let permissionType: SitePermissionType
            switch type {
            case .camera:
                permissionType = .camera
            case .microphone:
                permissionType = .microphone
            case .cameraAndMicrophone:
                permissionType = .camera
            @unknown default:
                permissionType = .camera
            }
            viewModel.shouldAllowPermissionRequest(type: permissionType, host: origin.host) { isAllowed in
                decisionHandler(isAllowed ? .grant : .deny)
            }
        }

        @available(macOS 13.0, *)
        func webView(
            _ webView: WKWebView,
            requestGeolocationPermissionForFrame frame: WKFrameInfo,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            let host = frame.request.url?.host?.lowercased()
            viewModel.shouldAllowPermissionRequest(type: .location, host: host) { isAllowed in
                decisionHandler(isAllowed ? .grant : .deny)
            }
        }

        @available(macOS 13.0, *)
        func webView(
            _ webView: WKWebView,
            requestNotificationPermissionFor securityOrigin: WKSecurityOrigin,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            viewModel.shouldAllowPermissionRequest(type: .notifications, host: securityOrigin.host) { isAllowed in
                decisionHandler(isAllowed ? .grant : .deny)
            }
        }
    }
}
