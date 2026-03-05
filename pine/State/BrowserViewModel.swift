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

    var sortedTabs: [Tab] {
        tabs
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
        normalizePinnedOrdering()
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

    func duplicateTab(id: UUID) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let sourceTab = tabs[sourceIndex]
        let duplicate = Tab(
            urlString: sourceTab.urlString,
            title: sourceTab.title,
            isPrivate: sourceTab.isPrivate,
            isPinned: sourceTab.isPinned
        )

        tabs.insert(duplicate, at: min(sourceIndex + 1, tabs.count))
        normalizePinnedOrdering()
        selectedTabID = duplicate.id
        load(urlInput: sourceTab.urlString, in: duplicate.id)
    }

    func closeOtherTabs(keeping id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }

        let removedIDs = tabs.filter { $0.id != id }.map(\.id)
        tabs.removeAll { $0.id != id }
        selectedTabID = id

        for removedID in removedIDs {
            webViews[removedID] = nil
            webViewObservers[removedID]?.invalidate()
            webViewObservers[removedID] = nil
        }
    }

    func closeTabsToRight(of id: UUID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        guard tabIndex < tabs.count - 1 else { return }
        let idsToRemove = tabs[(tabIndex + 1)...].map(\.id)

        tabs.removeAll { idsToRemove.contains($0.id) }

        for removedID in idsToRemove {
            webViews[removedID] = nil
            webViewObservers[removedID]?.invalidate()
            webViewObservers[removedID] = nil
        }

        if let currentSelectedTabID = selectedTabID, !tabs.contains(where: { $0.id == currentSelectedTabID }) {
            selectedTabID = id
        }
    }

    func setTabPinned(id: UUID, isPinned: Bool) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isPinned = isPinned
        normalizePinnedOrdering()
    }

    func reorderTab(draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID else { return }
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == draggedID }) else { return }
        guard let destinationIndex = tabs.firstIndex(where: { $0.id == targetID }) else { return }

        let movedTab = tabs.remove(at: sourceIndex)
        let adjustedDestination = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        tabs.insert(movedTab, at: adjustedDestination)
        normalizePinnedOrdering()
    }

    func selectTab(atOneBasedIndex index: Int) {
        guard index >= 1 else { return }
        guard index <= tabs.count else { return }
        selectedTabID = tabs[index - 1].id
    }

    func cycleTab(forward: Bool) {
        guard let selectedTabID else { return }
        guard let currentIndex = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        guard !tabs.isEmpty else { return }

        let nextIndex: Int
        if forward {
            nextIndex = (currentIndex + 1) % tabs.count
        } else {
            nextIndex = (currentIndex - 1 + tabs.count) % tabs.count
        }
        self.selectedTabID = tabs[nextIndex].id
    }

    func tabsMatching(query: String) -> [Tab] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return tabs }

        let lowered = trimmedQuery.lowercased()
        return tabs.filter { tab in
            tab.title.lowercased().contains(lowered) || tab.urlString.lowercased().contains(lowered)
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

    private func normalizePinnedOrdering() {
        let pinnedTabs = tabs.filter(\.isPinned)
        let unpinnedTabs = tabs.filter { !$0.isPinned }
        tabs = pinnedTabs + unpinnedTabs
    }
}
