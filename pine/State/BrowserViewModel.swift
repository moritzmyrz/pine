import Combine
import Foundation
import WebKit

final class BrowserViewModel: ObservableObject {
    @Published var tabs: [Tab]
    @Published var selectedTabID: UUID?

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

    func newTab(urlString: String = "https://example.com") {
        let tab = Tab(urlString: urlString)
        tabs.append(tab)
        selectedTabID = tab.id
        load(urlInput: urlString, in: tab.id)
    }

    func closeTab(id: UUID) {
        tabs.removeAll { $0.id == id }
        webViews[id] = nil

        guard !tabs.isEmpty else {
            selectedTabID = nil
            return
        }

        if selectedTabID == id {
            selectedTabID = tabs[0].id
        } else if let selectedTabID, tabs.contains(where: { $0.id == selectedTabID }) {
            self.selectedTabID = selectedTabID
        } else {
            selectedTabID = tabs[0].id
        }
    }

    func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
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
