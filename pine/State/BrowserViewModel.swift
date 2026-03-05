import Combine
import Foundation
import WebKit

final class BrowserViewModel: ObservableObject {
    @Published var tabs: [Tab]
    @Published var selectedTabID: UUID?
    @Published var addressBarFocusToken = UUID()
    @Published private(set) var shouldSelectAllInAddressBar = false
    let historyStore: HistoryStore
    let bookmarksStore: BookmarksStore
    let downloadManager: DownloadManager

    // Keep WKWebView instances in the view model so Tab stays plain state data.
    // This works well with SwiftUI value-driven updates on macOS.
    private var webViews: [UUID: WKWebView] = [:]
    private var webViewObservers: [UUID: WebViewObservers] = [:]
    private var cancellables: Set<AnyCancellable> = []

    private struct WebViewObservers {
        let titleObserver: NSKeyValueObservation
        let urlObserver: NSKeyValueObservation
        let isLoadingObserver: NSKeyValueObservation
        let estimatedProgressObserver: NSKeyValueObservation
        let canGoBackObserver: NSKeyValueObservation
        let canGoForwardObserver: NSKeyValueObservation

        func invalidate() {
            titleObserver.invalidate()
            urlObserver.invalidate()
            isLoadingObserver.invalidate()
            estimatedProgressObserver.invalidate()
            canGoBackObserver.invalidate()
            canGoForwardObserver.invalidate()
        }
    }

    var selectedTab: Tab? {
        guard let selectedTabID else { return nil }
        return tabs.first(where: { $0.id == selectedTabID })
    }

    init(
        historyStore: HistoryStore = HistoryStore(),
        bookmarksStore: BookmarksStore = BookmarksStore(),
        downloadManager: DownloadManager = DownloadManager()
    ) {
        self.historyStore = historyStore
        self.bookmarksStore = bookmarksStore
        self.downloadManager = downloadManager
        let firstTab = Tab(urlString: "https://example.com")
        tabs = [firstTab]
        selectedTabID = firstTab.id
        load(urlInput: firstTab.urlString, in: firstTab.id)

        bookmarksStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    deinit {
        for observers in webViewObservers.values {
            observers.invalidate()
        }
    }

    @discardableResult
    func newTab(
        urlString: String = "https://example.com",
        shouldSelect: Bool = true,
        shouldLoad: Bool = true,
        focusAddressBar: Bool = false,
        isPrivate: Bool = false
    ) -> UUID {
        let tab = Tab(urlString: urlString, isPrivate: isPrivate)
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
    func newBlankTab(shouldSelect: Bool = true, isPrivate: Bool = false) -> UUID {
        newTab(urlString: "about:blank", shouldSelect: shouldSelect, shouldLoad: true, isPrivate: isPrivate)
    }

    @discardableResult
    func newPrivateTab(urlString: String = "https://example.com", focusAddressBar: Bool = false) -> UUID {
        newTab(urlString: urlString, focusAddressBar: focusAddressBar, isPrivate: true)
    }

    func closeTab(id: UUID) {
        guard let closedIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = (selectedTabID == id)

        tabs.removeAll { $0.id == id }
        webViews[id] = nil
        webViewObservers[id]?.invalidate()
        webViewObservers[id] = nil

        if tabs.isEmpty {
            _ = newBlankTab(shouldSelect: true, isPrivate: false)
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

    func openInNewTab(request: URLRequest?, fromTabID: UUID?) {
        let shouldUsePrivate = fromTabID.flatMap { sourceID in
            tabs.first(where: { $0.id == sourceID })?.isPrivate
        } ?? false
        let tabID = newBlankTab(shouldSelect: true, isPrivate: shouldUsePrivate)
        guard let request else { return }

        let webView = webView(for: tabID)
        webView.load(request)

        if let url = request.url, let index = tabs.firstIndex(where: { $0.id == tabID }) {
            tabs[index].urlString = url.absoluteString
        }
    }

    func requestAddressBarFocus(selectAll: Bool = false) {
        shouldSelectAllInAddressBar = selectAll
        addressBarFocusToken = UUID()
    }

    func consumeAddressBarSelectAllRequest() {
        shouldSelectAllInAddressBar = false
    }

    func webView(for tabID: UUID) -> WKWebView {
        if let webView = webViews[tabID] {
            return webView
        }

        let configuration = WKWebViewConfiguration()
        if tabs.first(where: { $0.id == tabID })?.isPrivate == true {
            configuration.websiteDataStore = .nonPersistent()
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webViews[tabID] = webView
        attachObservers(to: webView, tabID: tabID)
        return webView
    }

    func loadSelectedTab() {
        guard let selectedTab else { return }
        load(urlInput: selectedTab.urlString, in: selectedTab.id)
    }

    func loadSelectedTab(from urlInput: String) {
        guard let selectedTab else { return }

        if let index = tabs.firstIndex(where: { $0.id == selectedTab.id }) {
            tabs[index].urlString = urlInput
        }

        load(urlInput: urlInput, in: selectedTab.id)
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

    func recordHistoryForCompletedNavigation(tabID: UUID) {
        guard selectedTabID == tabID else { return }
        guard let webView = webViews[tabID], let url = webView.url else { return }

        let title = webView.title ?? selectedTab?.title ?? "New Tab"
        historyStore.addEntry(title: title, urlString: url.absoluteString)
    }

    func loadHistoryEntryInSelectedTab(_ entry: HistoryEntry) {
        loadSelectedTab(from: entry.urlString)
    }

    func loadBookmarkInSelectedTab(_ bookmark: Bookmark) {
        loadSelectedTab(from: bookmark.urlString)
    }

    func isCurrentPageBookmarked() -> Bool {
        guard let urlString = selectedPageURLString() else { return false }
        return bookmarksStore.bookmark(forURLString: urlString) != nil
    }

    func toggleBookmarkForSelectedTab() {
        guard let urlString = selectedPageURLString() else { return }

        let pageTitle = selectedTab?.title ?? ""
        bookmarksStore.toggleBookmark(title: pageTitle, urlString: urlString)
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

    private func attachObservers(to webView: WKWebView, tabID: UUID) {
        guard webViewObservers[tabID] == nil else { return }

        let observers = WebViewObservers(
            titleObserver: webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
                self?.syncTabStateOnMain(from: webView, for: tabID)
            },
            urlObserver: webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                self?.syncTabStateOnMain(from: webView, for: tabID)
            },
            isLoadingObserver: webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
                self?.syncTabStateOnMain(from: webView, for: tabID)
            },
            estimatedProgressObserver: webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                self?.syncTabStateOnMain(from: webView, for: tabID)
            },
            canGoBackObserver: webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
                self?.syncTabStateOnMain(from: webView, for: tabID)
            },
            canGoForwardObserver: webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
                self?.syncTabStateOnMain(from: webView, for: tabID)
            }
        )

        webViewObservers[tabID] = observers
    }

    private func syncTabStateOnMain(from webView: WKWebView, for tabID: UUID) {
        if Thread.isMainThread {
            syncTabState(from: webView, for: tabID)
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.syncTabState(from: webView, for: tabID)
        }
    }

    private func selectedPageURLString() -> String? {
        guard let selectedTabID else { return nil }

        if let currentURL = webViews[selectedTabID]?.url?.absoluteString, !currentURL.isEmpty {
            return currentURL
        }

        if let tabURL = selectedTab?.urlString, !tabURL.isEmpty {
            return tabURL
        }

        return nil
    }
}
