import AppKit
import Foundation
import WebKit

final class NavigationController {
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

    private let store: BrowserStore
    private let historyStore: HistoryStore
    private let bookmarksStore: BookmarksStore
    private let profileStore: ProfileStore
    private let sessionStore: SessionStore
    private let contentBlockerService: ContentBlockerService
    private let tabManager: TabManager
    private let downloadController: DownloadController

    private var webViews: [UUID: WKWebView] = [:]
    private var webViewObservers: [UUID: WebViewObservers] = [:]
    private var faviconCacheByHost: [String: Data] = [:]
    private var faviconTasks: [UUID: URLSessionDataTask] = [:]

    init(
        store: BrowserStore,
        historyStore: HistoryStore,
        bookmarksStore: BookmarksStore,
        profileStore: ProfileStore,
        sessionStore: SessionStore,
        contentBlockerService: ContentBlockerService,
        tabManager: TabManager,
        downloadController: DownloadController
    ) {
        self.store = store
        self.historyStore = historyStore
        self.bookmarksStore = bookmarksStore
        self.profileStore = profileStore
        self.sessionStore = sessionStore
        self.contentBlockerService = contentBlockerService
        self.tabManager = tabManager
        self.downloadController = downloadController
    }

    deinit {
        for observers in webViewObservers.values {
            observers.invalidate()
        }
        for task in faviconTasks.values {
            task.cancel()
        }
    }

    func cleanupTabResources(tabID: UUID) {
        webViews[tabID] = nil
        webViewObservers[tabID]?.invalidate()
        webViewObservers[tabID] = nil
        faviconTasks[tabID]?.cancel()
        faviconTasks[tabID] = nil
    }

    func webView(for tabID: UUID) -> WKWebView {
        if let webView = webViews[tabID] {
            applyStoredPageSettings(for: tabID, in: webView)
            return webView
        }

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        contentBlockerService.apply(to: configuration.userContentController)
        if let tab = store.tabs.first(where: { $0.id == tabID }), tab.isPrivate {
            configuration.websiteDataStore = .nonPersistent()
        } else if let tab = store.tabs.first(where: { $0.id == tabID }) {
            configuration.websiteDataStore = profileStore.websiteDataStore(for: tab.profileID)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = shouldEnableWebInspector()
        webViews[tabID] = webView
        attachObservers(to: webView, tabID: tabID)
        applyStoredPageSettings(for: tabID, in: webView)
        return webView
    }

    func loadURL(_ urlInput: String, in tabID: UUID) {
        guard let url = normalizedURL(from: urlInput) else { return }
        let webView = webView(for: tabID)
        webView.load(URLRequest(url: url))
        guard let index = store.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        store.tabs[index].urlString = url.absoluteString
    }

    func loadSelectedTab() {
        guard let selectedTab = store.selectedTab else { return }
        loadURL(selectedTab.urlString, in: selectedTab.id)
    }

    func loadSelectedTab(from urlInput: String) {
        guard let selectedTab = store.selectedTab else { return }
        if let index = store.tabs.firstIndex(where: { $0.id == selectedTab.id }) {
            store.tabs[index].urlString = urlInput
        }
        loadURL(urlInput, in: selectedTab.id)
    }

    func goBackSelectedTab() {
        guard let selectedTabID = store.selectedTabID,
              let webView = webViews[selectedTabID],
              webView.canGoBack else { return }
        webView.goBack()
    }

    func goForwardSelectedTab() {
        guard let selectedTabID = store.selectedTabID,
              let webView = webViews[selectedTabID],
              webView.canGoForward else { return }
        webView.goForward()
    }

    func reloadSelectedTab() {
        guard let selectedTabID = store.selectedTabID,
              let webView = webViews[selectedTabID] else { return }
        webView.reload()
    }

    func zoomInSelectedTab() { adjustZoomForSelectedTab(delta: 0.1) }
    func zoomOutSelectedTab() { adjustZoomForSelectedTab(delta: -0.1) }

    func resetZoomSelectedTab() {
        guard let selectedTabID = store.selectedTabID else { return }
        setZoomFactor(1.0, for: selectedTabID)
    }

    func toggleReaderModeForSelectedTab() {
        guard let selectedTabID = store.selectedTabID,
              let index = store.tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        store.tabs[index].isReaderModeEnabled.toggle()
        applyReaderModeIfNeeded(for: selectedTabID)
    }

    func syncTabState(from webView: WKWebView, for tabID: UUID) {
        guard let index = store.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let previousHost = host(from: store.tabs[index].urlString)

        store.tabs[index].title = (webView.title?.isEmpty == false) ? (webView.title ?? "New Tab") : "New Tab"
        store.tabs[index].urlString = webView.url?.absoluteString ?? store.tabs[index].urlString
        store.tabs[index].isLoading = webView.isLoading
        store.tabs[index].estimatedProgress = webView.estimatedProgress
        store.tabs[index].canGoBack = webView.canGoBack
        store.tabs[index].canGoForward = webView.canGoForward

        let currentHost = host(from: store.tabs[index].urlString)
        if currentHost != previousHost {
            if let currentHost, let cachedData = faviconCacheByHost[currentHost] {
                store.tabs[index].faviconData = cachedData
            } else {
                store.tabs[index].faviconData = nil
            }
        }
    }

    func recordHistoryForCompletedNavigation(tabID: UUID) {
        guard store.selectedTabID == tabID else { return }
        guard let webView = webViews[tabID], let url = webView.url else { return }
        let title = webView.title ?? store.selectedTab?.title ?? "New Tab"
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
        let pageTitle = store.selectedTab?.title ?? ""
        bookmarksStore.toggleBookmark(title: pageTitle, urlString: urlString)
    }

    func openInNewTab(request: URLRequest?, fromTabID: UUID?) {
        let sourceTab = fromTabID.flatMap { sourceID in store.tabs.first(where: { $0.id == sourceID }) }
        let shouldUsePrivate = sourceTab?.isPrivate ?? false
        let sourceProfileID = sourceTab?.profileID ?? store.currentProfileID
        let tabID = tabManager.newTab(
            urlString: "about:blank",
            shouldSelect: true,
            shouldLoad: true,
            isPrivate: shouldUsePrivate,
            profileID: sourceProfileID
        )
        guard let request else { return }
        let webView = webView(for: tabID)
        webView.load(request)
        if let url = request.url, let index = store.tabs.firstIndex(where: { $0.id == tabID }) {
            store.tabs[index].urlString = url.absoluteString
        }
    }

    func refreshFavicon(for tabID: UUID, from webView: WKWebView) {
        guard let index = store.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard let pageURL = webView.url,
              let host = pageURL.host?.lowercased(),
              !host.isEmpty else { return }
        if let cachedData = faviconCacheByHost[host] {
            store.tabs[index].faviconData = cachedData
            return
        }
        faviconTasks[tabID]?.cancel()
        resolveIconURLFromDOM(webView: webView, pageURL: pageURL) { [weak self] domIconURL in
            guard let self else { return }
            let fallbackURL = self.faviconFallbackURL(for: pageURL)
            var candidates: [URL] = []
            if let domIconURL { candidates.append(domIconURL) }
            if let fallbackURL { candidates.append(fallbackURL) }
            self.fetchFirstValidFavicon(for: tabID, host: host, candidates: candidates)
        }
    }

    func viewSourceForSelectedTab() {
        guard let urlString = selectedPageURLString(),
              let url = URL(string: urlString),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        _ = tabManager.newTab(urlString: "view-source:\(url.absoluteString)", shouldSelect: true, shouldLoad: true)
    }

    func openSelectedPageInSafari() {
        guard let urlString = selectedPageURLString(), let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyCleanLinkForSelectedTab() {
        guard let urlString = selectedPageURLString() else { return }
        let cleaned = cleanedURLStringConservatively(urlString) ?? urlString
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(cleaned, forType: .string)
    }

    func applyStoredPageSettings(for tabID: UUID, in webView: WKWebView) {
        guard let tab = store.tabs.first(where: { $0.id == tabID }) else { return }
        webView.pageZoom = tab.zoomFactor
        setReaderMode(in: webView, enabled: tab.isReaderModeEnabled)
    }

    func applyContentBlockingToAllWebViews() {
        for webView in webViews.values {
            contentBlockerService.apply(to: webView.configuration.userContentController)
        }
    }

    func setEnableWebInspectorInDebugBuilds(_ enabled: Bool) {
        store.sessionSettings.enableWebInspectorInDebugBuilds = enabled
        sessionStore.saveSettings(store.sessionSettings)
        applyInspectablePreferenceToAllWebViews()
    }

    func setEnableWebInspectorInReleaseBuilds(_ enabled: Bool) {
        store.sessionSettings.enableWebInspectorInReleaseBuilds = enabled
        sessionStore.saveSettings(store.sessionSettings)
        applyInspectablePreferenceToAllWebViews()
    }

    func attachDownload(_ download: WKDownload, webView: WKWebView, suggestedFilename: String, sourceURL: URL?) {
        downloadController.downloadManager.track(
            download: download,
            webView: webView,
            suggestedFilename: suggestedFilename,
            sourceURL: sourceURL
        )
    }

    private func normalizedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let directURL = URL(string: trimmed), directURL.scheme != nil { return directURL }
        if !trimmed.contains(" "), trimmed.contains("."), let httpsURL = URL(string: "https://\(trimmed)") {
            return httpsURL
        }
        guard let encodedQuery = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://duckduckgo.com/?q=\(encodedQuery)")
    }

    private func attachObservers(to webView: WKWebView, tabID: UUID) {
        guard webViewObservers[tabID] == nil else { return }
        let observers = WebViewObservers(
            titleObserver: webView.observe(\.title, options: [.new]) { [weak self] webView, _ in self?.syncTabStateOnMain(from: webView, for: tabID) },
            urlObserver: webView.observe(\.url, options: [.new]) { [weak self] webView, _ in self?.syncTabStateOnMain(from: webView, for: tabID) },
            isLoadingObserver: webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in self?.syncTabStateOnMain(from: webView, for: tabID) },
            estimatedProgressObserver: webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in self?.syncTabStateOnMain(from: webView, for: tabID) },
            canGoBackObserver: webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in self?.syncTabStateOnMain(from: webView, for: tabID) },
            canGoForwardObserver: webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in self?.syncTabStateOnMain(from: webView, for: tabID) }
        )
        webViewObservers[tabID] = observers
    }

    private func syncTabStateOnMain(from webView: WKWebView, for tabID: UUID) {
        if Thread.isMainThread {
            syncTabState(from: webView, for: tabID)
        } else {
            DispatchQueue.main.async { [weak self] in self?.syncTabState(from: webView, for: tabID) }
        }
    }

    private func selectedPageURLString() -> String? {
        guard let selectedTabID = store.selectedTabID else { return nil }
        if let currentURL = webViews[selectedTabID]?.url?.absoluteString, !currentURL.isEmpty { return currentURL }
        if let tabURL = store.selectedTab?.urlString, !tabURL.isEmpty { return tabURL }
        return nil
    }

    private func adjustZoomForSelectedTab(delta: Double) {
        guard let selectedTabID = store.selectedTabID,
              let index = store.tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        setZoomFactor(store.tabs[index].zoomFactor + delta, for: selectedTabID)
    }

    private func setZoomFactor(_ value: Double, for tabID: UUID) {
        guard let index = store.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let clamped = min(max(value, 0.5), 3.0)
        store.tabs[index].zoomFactor = clamped
        webViews[tabID]?.pageZoom = clamped
    }

    private func applyReaderModeIfNeeded(for tabID: UUID) {
        guard let webView = webViews[tabID], let tab = store.tabs.first(where: { $0.id == tabID }) else { return }
        setReaderMode(in: webView, enabled: tab.isReaderModeEnabled)
    }

    private func resolveIconURLFromDOM(webView: WKWebView, pageURL: URL, completion: @escaping (URL?) -> Void) {
        let script = "(() => { const selectors = ['link[rel~=\"apple-touch-icon\"]','link[rel~=\"apple-touch-icon-precomposed\"]','link[rel~=\"icon\"]','link[rel=\"shortcut icon\"]']; for (const selector of selectors) { const element = document.querySelector(selector); if (element && element.href) { return element.href; } } return null; })();"
        webView.evaluateJavaScript(script) { value, _ in
            guard let iconURLString = value as? String, !iconURLString.isEmpty else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            if let directURL = URL(string: iconURLString) {
                DispatchQueue.main.async { completion(directURL) }
                return
            }
            DispatchQueue.main.async { completion(URL(string: iconURLString, relativeTo: pageURL)?.absoluteURL) }
        }
    }

    private func fetchFirstValidFavicon(for tabID: UUID, host: String, candidates: [URL]) {
        guard let firstCandidate = candidates.first else { return }
        fetchFavicon(at: firstCandidate, for: tabID, host: host) { [weak self] success in
            guard let self, !success else { return }
            self.fetchFirstValidFavicon(for: tabID, host: host, candidates: Array(candidates.dropFirst()))
        }
    }

    private func fetchFavicon(at url: URL, for tabID: UUID, host: String, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            DispatchQueue.main.async { self.faviconTasks[tabID] = nil }
            guard error == nil,
                  let response = response as? HTTPURLResponse,
                  (200..<400).contains(response.statusCode),
                  let data,
                  !data.isEmpty else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let mimeType = response.mimeType?.lowercased() ?? ""
            guard mimeType.hasPrefix("image/") || mimeType.contains("icon") else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            DispatchQueue.main.async {
                self.faviconCacheByHost[host] = data
                if let index = self.store.tabs.firstIndex(where: { $0.id == tabID }) {
                    self.store.tabs[index].faviconData = data
                }
                completion(true)
            }
        }
        faviconTasks[tabID] = task
        task.resume()
    }

    private func faviconFallbackURL(for pageURL: URL) -> URL? {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: true) else { return nil }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func host(from urlString: String) -> String? { URL(string: urlString)?.host?.lowercased() }

    private func setReaderMode(in webView: WKWebView, enabled: Bool) {
        let script = enabled
            ? "(() => { try { const id = 'pine-reader-mode-lite'; const hasPasswordField = !!document.querySelector('input[type=\"password\"]'); if (hasPasswordField) { const existing = document.getElementById(id); if (existing) { existing.remove(); } return; } let style = document.getElementById(id); if (!style) { style = document.createElement('style'); style.id = id; document.head.appendChild(style); } style.textContent = `html, body { max-width: 760px !important; margin: 0 auto !important; padding: 0 16px !important; font-size: 19px !important; line-height: 1.7 !important; word-break: break-word !important; } img, video, iframe, table, pre { max-width: 100% !important; } pre, code { font-size: 0.9em !important; line-height: 1.5 !important; }`; } catch (_) {} })();"
            : "(() => { try { const style = document.getElementById('pine-reader-mode-lite'); if (style) { style.remove(); } } catch (_) {} })();"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func applyInspectablePreferenceToAllWebViews() {
        let enabled = shouldEnableWebInspector()
        for webView in webViews.values {
            webView.isInspectable = enabled
        }
    }

    private func shouldEnableWebInspector() -> Bool {
#if DEBUG
        return store.sessionSettings.enableWebInspectorInDebugBuilds
#else
        return store.sessionSettings.enableWebInspectorInReleaseBuilds
#endif
    }

    private func cleanedURLStringConservatively(_ input: String) -> String? {
        guard let url = URL(string: input),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        guard let queryItems = components.queryItems, !queryItems.isEmpty else { return input }
        let knownTrackingKeys: Set<String> = ["fbclid", "gclid"]
        let filtered = queryItems.filter { item in
            let key = item.name.lowercased()
            return !key.hasPrefix("utm_") && !knownTrackingKeys.contains(key)
        }
        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.url?.absoluteString ?? input
    }
}
