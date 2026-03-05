import Combine
import Foundation
import WebKit

final class BrowserViewModel: ObservableObject {
    @Published var tabs: [Tab]
    @Published var selectedTabID: UUID?
    @Published var addressBarFocusToken = UUID()

    // Keep WKWebView instances in the view model so Tab stays plain state data.
    // This works well with SwiftUI value-driven updates on macOS.
    private var webViews: [UUID: WKWebView] = [:]

    var selectedTab: Tab? {
        guard let selectedTabID else { return nil }
        return tabs.first(where: { $0.id == selectedTabID })
    }

    init() {
        let firstTab = Tab(urlString: "https://example.com")
        tabs = [firstTab]
        selectedTabID = firstTab.id
        load(urlInput: firstTab.urlString, in: firstTab.id)
    }

    @discardableResult
    func newTab(
        urlString: String = "https://example.com",
        shouldSelect: Bool = true,
        shouldLoad: Bool = true,
        focusAddressBar: Bool = false
    ) -> UUID {
        let tab = Tab(urlString: urlString)
        tabs.append(tab)
        if shouldSelect {
            selectedTabID = tab.id
        }

        if shouldLoad {
            load(urlInput: urlString, in: tab.id)
        }

        if focusAddressBar {
            requestAddressBarFocus()
        }

        return tab.id
    }

    @discardableResult
    func newBlankTab(shouldSelect: Bool = true) -> UUID {
        newTab(urlString: "about:blank", shouldSelect: shouldSelect, shouldLoad: true)
    }

    func closeTab(id: UUID) {
        guard let closedIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = (selectedTabID == id)

        tabs.removeAll { $0.id == id }
        webViews[id] = nil

        if tabs.isEmpty {
            _ = newBlankTab(shouldSelect: true)
            return
        }

        if wasSelected {
            let nextIndex = min(closedIndex, tabs.count - 1)
            selectedTabID = tabs[nextIndex].id
            return
        }

        if let selectedTabID, tabs.contains(where: { $0.id == selectedTabID }) {
            return
        }

        if let firstTab = tabs.first {
            selectedTabID = firstTab.id
        }
    }

    func closeCurrentTab() {
        guard let selectedTabID else { return }
        closeTab(id: selectedTabID)
    }

    func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    func openInNewTab(request: URLRequest?) {
        let tabID = newBlankTab(shouldSelect: true)
        guard let request else { return }

        let webView = webView(for: tabID)
        webView.load(request)

        if let url = request.url, let index = tabs.firstIndex(where: { $0.id == tabID }) {
            tabs[index].urlString = url.absoluteString
        }
    }

    func requestAddressBarFocus() {
        addressBarFocusToken = UUID()
    }

    func webView(for tabID: UUID) -> WKWebView {
        if let webView = webViews[tabID] {
            return webView
        }

        let webView = WKWebView(frame: .zero)
        webViews[tabID] = webView
        return webView
    }

    func loadSelectedTab() {
        guard let selectedTab else { return }
        load(urlInput: selectedTab.urlString, in: selectedTab.id)
    }

    func goBackSelectedTab() {
        guard
            let selectedTabID,
            let webView = webViews[selectedTabID],
            webView.canGoBack
        else {
            return
        }

        webView.goBack()
    }

    func goForwardSelectedTab() {
        guard
            let selectedTabID,
            let webView = webViews[selectedTabID],
            webView.canGoForward
        else {
            return
        }

        webView.goForward()
    }

    func reloadSelectedTab() {
        guard
            let selectedTabID,
            let webView = webViews[selectedTabID]
        else {
            return
        }

        webView.reload()
    }

    func syncTabState(from webView: WKWebView, for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }

        if let title = webView.title, !title.isEmpty {
            tabs[index].title = title
        } else {
            tabs[index].title = "New Tab"
        }
        tabs[index].urlString = webView.url?.absoluteString ?? tabs[index].urlString
        tabs[index].isLoading = webView.isLoading
        tabs[index].estimatedProgress = webView.estimatedProgress
        tabs[index].canGoBack = webView.canGoBack
        tabs[index].canGoForward = webView.canGoForward
    }

    private func load(urlInput: String, in tabID: UUID) {
        guard let url = normalizedURL(from: urlInput) else { return }

        let webView = webView(for: tabID)
        webView.load(URLRequest(url: url))

        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].urlString = url.absoluteString
    }

    private func normalizedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let directURL = URL(string: trimmed), directURL.scheme != nil {
            return directURL
        }

        if looksLikeURL(trimmed), let httpsURL = URL(string: "https://\(trimmed)") {
            return httpsURL
        }

        guard let encodedQuery = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        return URL(string: "https://duckduckgo.com/?q=\(encodedQuery)")
    }

    private func looksLikeURL(_ input: String) -> Bool {
        !input.contains(" ") && input.contains(".")
    }
}
