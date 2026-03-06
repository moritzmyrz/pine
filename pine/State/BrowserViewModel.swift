import AppKit
import Combine
import Foundation
import WebKit

final class BrowserViewModel: ObservableObject {
    @Published var tabs: [Tab]
    @Published var selectedTabID: UUID?
    @Published var profiles: [Profile]
    @Published var currentProfileID: UUID
    @Published var sessionSettings: BrowserSettings
    @Published var permissionDefaults: PermissionDefaults
    @Published var trackerBlockingMode: TrackerBlockingMode
    @Published var addressBarFocusToken = UUID()
    @Published private(set) var shouldSelectAllInAddressBar = false
    let historyStore: HistoryStore
    let bookmarksStore: BookmarksStore
    let downloadManager: DownloadManager
    let sessionStore: SessionStore
    let profileStore: ProfileStore
    let sitePermissionsStore: SitePermissionsStore
    let contentBlockerService: ContentBlockerService

    // Keep WKWebView instances in the view model so Tab stays plain state data.
    // This works well with SwiftUI value-driven updates on macOS.
    private var webViews: [UUID: WKWebView] = [:]
    private var webViewObservers: [UUID: WebViewObservers] = [:]
    private var faviconCacheByHost: [String: Data] = [:]
    private var faviconTasks: [UUID: URLSessionDataTask] = [:]
    private var closedTabsStack: [ClosedTabState] = []
    private var sitePermissionsByHost: [String: SitePermissionEntry]
    private var cancellables: Set<AnyCancellable> = []

    private struct ClosedTabState {
        let profileID: UUID
        let urlString: String
        let title: String
        let isPrivate: Bool
        let isPinned: Bool
    }

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

    var currentProfile: Profile? {
        profiles.first(where: { $0.id == currentProfileID })
    }

    init(
        historyStore: HistoryStore = HistoryStore(),
        bookmarksStore: BookmarksStore = BookmarksStore(),
        downloadManager: DownloadManager = DownloadManager(),
        sessionStore: SessionStore = SessionStore(),
        profileStore: ProfileStore = ProfileStore(),
        sitePermissionsStore: SitePermissionsStore = SitePermissionsStore(),
        contentBlockerService: ContentBlockerService = ContentBlockerService()
    ) {
        self.historyStore = historyStore
        self.bookmarksStore = bookmarksStore
        self.downloadManager = downloadManager
        self.sessionStore = sessionStore
        self.profileStore = profileStore
        self.sitePermissionsStore = sitePermissionsStore
        self.contentBlockerService = contentBlockerService
        tabs = []
        selectedTabID = nil
        permissionDefaults = sitePermissionsStore.loadPermissionDefaults()
        trackerBlockingMode = contentBlockerService.mode
        sitePermissionsByHost = sitePermissionsStore.loadSitePermissions()
        let initialSettings = sessionStore.loadSettings()
        sessionSettings = initialSettings
        let loadedProfiles = profileStore.loadProfiles()
        profiles = loadedProfiles
        let defaultProfileID = loadedProfiles.first(where: \.isDefault)?.id ?? loadedProfiles[0].id
        let savedProfileID = initialSettings.currentProfileID
        let resolvedCurrentProfileID = savedProfileID.flatMap { candidate in
            loadedProfiles.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? defaultProfileID
        currentProfileID = resolvedCurrentProfileID

        if sessionSettings.restorePreviousSession,
           let savedSession = sessionStore.loadSession(),
           !savedSession.tabs.isEmpty {
            tabs = savedSession.tabs.map { persisted in
                let restoredProfileID = persisted.profileID.flatMap { id in
                    loadedProfiles.contains(where: { $0.id == id }) ? id : nil
                } ?? resolvedCurrentProfileID
                return Tab(
                    id: persisted.id,
                    profileID: restoredProfileID,
                    urlString: persisted.urlString,
                    title: persisted.title ?? "New Tab",
                    isPrivate: persisted.isPrivate,
                    isPinned: persisted.isPinned,
                    lastSelectedAt: persisted.lastSelectedAt
                )
            }
            normalizePinnedOrdering()
            if let selectedID = savedSession.selectedTabID, tabs.contains(where: { $0.id == selectedID }) {
                setSelectedTabID(selectedID)
            } else {
                setSelectedTabID(tabs.first?.id)
            }
            for tab in tabs {
                load(urlInput: tab.urlString, in: tab.id)
            }
        } else {
            let firstTab = Tab(profileID: resolvedCurrentProfileID, urlString: "https://example.com", lastSelectedAt: Date())
            tabs = [firstTab]
            setSelectedTabID(firstTab.id)
            load(urlInput: firstTab.urlString, in: firstTab.id)
        }

        sessionSettings.currentProfileID = resolvedCurrentProfileID
        sessionStore.saveSettings(sessionSettings)

        bookmarksStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineNewTab)
            .sink { [weak self] _ in
                self?.newTab(focusAddressBar: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineNewPrivateTab)
            .sink { [weak self] _ in
                self?.newPrivateTab(focusAddressBar: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineCloseTab)
            .sink { [weak self] _ in
                self?.closeCurrentTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineReload)
            .sink { [weak self] _ in
                self?.reloadSelectedTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineGoBack)
            .sink { [weak self] _ in
                self?.goBackSelectedTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineGoForward)
            .sink { [weak self] _ in
                self?.goForwardSelectedTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineCycleTabsBackward)
            .sink { [weak self] _ in
                self?.cycleTab(forward: false)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineCycleTabsForward)
            .sink { [weak self] _ in
                self?.cycleTab(forward: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineSelectTabAtIndex)
            .sink { [weak self] notification in
                guard let index = notification.userInfo?["index"] as? Int else { return }
                self?.selectTab(atOneBasedIndex: index)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineReopenClosedTab)
            .sink { [weak self] _ in
                self?.reopenClosedTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineZoomIn)
            .sink { [weak self] _ in
                self?.zoomInSelectedTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineZoomOut)
            .sink { [weak self] _ in
                self?.zoomOutSelectedTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineZoomReset)
            .sink { [weak self] _ in
                self?.resetZoomSelectedTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineToggleReaderMode)
            .sink { [weak self] _ in
                self?.toggleReaderModeForSelectedTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineViewSource)
            .sink { [weak self] _ in
                self?.viewSourceForSelectedTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineOpenCurrentPageInSafari)
            .sink { [weak self] _ in
                self?.openSelectedPageInSafari()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .pineCopyCleanLink)
            .sink { [weak self] _ in
                self?.copyCleanLinkForSelectedTab()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.persistSession()
            }
            .store(in: &cancellables)

        Timer.publish(every: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.persistSession()
            }
            .store(in: &cancellables)

        contentBlockerService.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.trackerBlockingMode = mode
                self?.applyContentBlockingToAllWebViews()
            }
            .store(in: &cancellables)

        contentBlockerService.onRuleListDidChange = { [weak self] in
            DispatchQueue.main.async {
                self?.applyContentBlockingToAllWebViews()
            }
        }
    }

    deinit {
        for observers in webViewObservers.values {
            observers.invalidate()
        }
        for task in faviconTasks.values {
            task.cancel()
        }
    }

    @discardableResult
    func newTab(
        urlString: String = "https://example.com",
        shouldSelect: Bool = true,
        shouldLoad: Bool = true,
        focusAddressBar: Bool = false,
        isPrivate: Bool = false,
        profileID: UUID? = nil
    ) -> UUID {
        let targetProfileID = profileID ?? currentProfileID
        let tab = Tab(profileID: targetProfileID, urlString: urlString, isPrivate: isPrivate)
        tabs.append(tab)
        normalizePinnedOrdering()
        if shouldSelect {
            setSelectedTabID(tab.id)
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
        newTab(urlString: "about:blank", shouldSelect: shouldSelect, shouldLoad: true, isPrivate: isPrivate, profileID: currentProfileID)
    }

    @discardableResult
    func newPrivateTab(urlString: String = "https://example.com", focusAddressBar: Bool = false) -> UUID {
        newTab(urlString: urlString, focusAddressBar: focusAddressBar, isPrivate: true, profileID: currentProfileID)
    }

    func closeTab(id: UUID) {
        guard let closedIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = (selectedTabID == id)
        let closedTab = tabs[closedIndex]
        pushClosedTabState(for: closedTab)

        tabs.removeAll { $0.id == id }
        webViews[id] = nil
        webViewObservers[id]?.invalidate()
        webViewObservers[id] = nil
        faviconTasks[id]?.cancel()
        faviconTasks[id] = nil

        if tabs.isEmpty {
            _ = newBlankTab(shouldSelect: true, isPrivate: false)
            return
        }

        if wasSelected {
            let nextIndex = min(closedIndex, tabs.count - 1)
            setSelectedTabID(tabs[nextIndex].id)
            return
        }

        if let selectedTabID, tabs.contains(where: { $0.id == selectedTabID }) {
            return
        }

        if let firstTab = tabs.first {
            setSelectedTabID(firstTab.id)
        }
    }

    func duplicateTab(id: UUID) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let sourceTab = tabs[sourceIndex]
        let duplicate = Tab(
            profileID: sourceTab.profileID,
            urlString: sourceTab.urlString,
            title: sourceTab.title,
            isPrivate: sourceTab.isPrivate,
            isPinned: sourceTab.isPinned,
            zoomFactor: sourceTab.zoomFactor,
            isReaderModeEnabled: sourceTab.isReaderModeEnabled,
            faviconData: sourceTab.faviconData
        )

        tabs.insert(duplicate, at: min(sourceIndex + 1, tabs.count))
        normalizePinnedOrdering()
        setSelectedTabID(duplicate.id)
        load(urlInput: sourceTab.urlString, in: duplicate.id)
    }

    func closeOtherTabs(keeping id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }

        let removedTabs = tabs.filter { $0.id != id }
        for tab in removedTabs {
            pushClosedTabState(for: tab)
        }
        let removedIDs = tabs.filter { $0.id != id }.map(\.id)
        tabs.removeAll { $0.id != id }
        setSelectedTabID(id)

        for removedID in removedIDs {
            webViews[removedID] = nil
            webViewObservers[removedID]?.invalidate()
            webViewObservers[removedID] = nil
            faviconTasks[removedID]?.cancel()
            faviconTasks[removedID] = nil
        }
    }

    func closeTabsToRight(of id: UUID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        guard tabIndex < tabs.count - 1 else { return }
        let removedTabs = Array(tabs[(tabIndex + 1)...])
        for tab in removedTabs {
            pushClosedTabState(for: tab)
        }
        let idsToRemove = tabs[(tabIndex + 1)...].map(\.id)

        tabs.removeAll { idsToRemove.contains($0.id) }

        for removedID in idsToRemove {
            webViews[removedID] = nil
            webViewObservers[removedID]?.invalidate()
            webViewObservers[removedID] = nil
            faviconTasks[removedID]?.cancel()
            faviconTasks[removedID] = nil
        }

        if let currentSelectedTabID = selectedTabID, !tabs.contains(where: { $0.id == currentSelectedTabID }) {
            setSelectedTabID(id)
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
        setSelectedTabID(tabs[index - 1].id)
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
        setSelectedTabID(tabs[nextIndex].id)
    }

    func tabsMatching(query: String) -> [Tab] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return tabs }

        let lowered = trimmedQuery.lowercased()
        return tabs.filter { tab in
            tab.title.lowercased().contains(lowered) || tab.urlString.lowercased().contains(lowered)
        }
    }

    func profileName(for profileID: UUID) -> String {
        profiles.first(where: { $0.id == profileID })?.name ?? "Unknown"
    }

    func closeCurrentTab() {
        guard let selectedTabID else { return }
        closeTab(id: selectedTabID)
    }

    func reopenClosedTab() {
        guard let closed = closedTabsStack.popLast() else { return }
        let reopenedID = newTab(
            urlString: closed.urlString,
            shouldSelect: true,
            shouldLoad: true,
            isPrivate: closed.isPrivate,
            profileID: closed.profileID
        )

        if let index = tabs.firstIndex(where: { $0.id == reopenedID }) {
            tabs[index].title = closed.title
            tabs[index].isPinned = closed.isPinned
            tabs[index].lastSelectedAt = Date()
        }
        normalizePinnedOrdering()
    }

    func setRestorePreviousSessionEnabled(_ enabled: Bool) {
        sessionSettings.restorePreviousSession = enabled
        sessionStore.saveSettings(sessionSettings)
        if enabled {
            persistSession()
        } else {
            sessionStore.clearSession()
        }
    }

    func setIncludePrivateTabsInSession(_ enabled: Bool) {
        sessionSettings.includePrivateTabsInSession = enabled
        sessionStore.saveSettings(sessionSettings)
        persistSession()
    }

    func selectProfile(id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        currentProfileID = id
        sessionSettings.currentProfileID = id
        sessionStore.saveSettings(sessionSettings)

        if let currentSelectedID = selectedTabID,
           tabs.first(where: { $0.id == currentSelectedID })?.profileID == id {
            return
        }

        if let existing = tabs.last(where: { $0.profileID == id }) {
            setSelectedTabID(existing.id)
        } else {
            _ = newBlankTab(shouldSelect: true, isPrivate: false)
        }
    }

    @discardableResult
    func createProfile(named name: String?) -> UUID {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = "Profile \(profiles.count + 1)"
        let profile = Profile(name: trimmed.isEmpty ? fallbackName : trimmed, isDefault: false)
        profiles.append(profile)
        profileStore.saveProfiles(profiles)
        return profile.id
    }

    func renameProfile(id: UUID, to newName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profiles[index].name = trimmed
        profileStore.saveProfiles(profiles)
    }

    func canDeleteProfile(id: UUID) -> Bool {
        guard let profile = profiles.first(where: { $0.id == id }) else { return false }
        if profile.isDefault {
            return false
        }
        return profiles.count > 1
    }

    func deleteProfile(id: UUID) {
        guard canDeleteProfile(id: id) else { return }

        let tabsInProfile = tabs.filter { $0.profileID == id }
        for tab in tabsInProfile {
            webViews[tab.id] = nil
            webViewObservers[tab.id]?.invalidate()
            webViewObservers[tab.id] = nil
            faviconTasks[tab.id]?.cancel()
            faviconTasks[tab.id] = nil
        }
        tabs.removeAll { $0.profileID == id }

        profiles.removeAll { $0.id == id }
        profileStore.saveProfiles(profiles)
        profileStore.deleteStoredWebsiteData(for: id) {}

        if currentProfileID == id {
            let fallbackProfileID = profiles.first(where: \.isDefault)?.id ?? profiles.first?.id
            if let fallbackProfileID {
                currentProfileID = fallbackProfileID
                sessionSettings.currentProfileID = fallbackProfileID
                sessionStore.saveSettings(sessionSettings)
            }
        }

        if let selectedTabID, tabs.contains(where: { $0.id == selectedTabID }) {
            if let selectedTab = tabs.first(where: { $0.id == selectedTabID }),
               selectedTab.profileID != currentProfileID,
               let replacement = tabs.last(where: { $0.profileID == currentProfileID }) {
                setSelectedTabID(replacement.id)
            }
        } else {
            if let replacement = tabs.last(where: { $0.profileID == currentProfileID }) {
                setSelectedTabID(replacement.id)
            } else {
                _ = newBlankTab(shouldSelect: true, isPrivate: false)
            }
        }

        closedTabsStack.removeAll { $0.profileID == id }
        persistSession()
    }

    func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        setSelectedTabID(id)
        if let webView = webViews[id] {
            applyStoredPageSettings(for: id, in: webView)
        }
    }

    func openInNewTab(request: URLRequest?, fromTabID: UUID?) {
        let sourceTab = fromTabID.flatMap { sourceID in
            tabs.first(where: { $0.id == sourceID })
        }
        let shouldUsePrivate = sourceTab?.isPrivate ?? false
        let sourceProfileID = sourceTab?.profileID ?? currentProfileID
        let tabID = newTab(
            urlString: "about:blank",
            shouldSelect: true,
            shouldLoad: true,
            isPrivate: shouldUsePrivate,
            profileID: sourceProfileID
        )
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

    func currentSiteHost() -> String? {
        guard let selectedTab else { return nil }
        return host(from: selectedTab.urlString)
    }

    func permissionValue(for type: SitePermissionType, host: String) -> SitePermissionValue {
        let normalized = normalizedHost(host)
        if let entry = sitePermissionsByHost[normalized] {
            return entry.value(for: type)
        }
        return defaultPermissionValue(for: type)
    }

    func setPermissionValue(_ value: SitePermissionValue, for type: SitePermissionType, host: String) {
        let normalized = normalizedHost(host)
        var entry = sitePermissionsByHost[normalized] ?? SitePermissionEntry.default
        entry.setValue(value, for: type)
        sitePermissionsByHost[normalized] = entry
        sitePermissionsStore.saveSitePermissions(sitePermissionsByHost)
        objectWillChange.send()
    }

    func setBlockPopupsByDefault(_ enabled: Bool) {
        permissionDefaults.blockPopupsByDefault = enabled
        sitePermissionsStore.savePermissionDefaults(permissionDefaults)
    }

    func setAskCameraAndMicrophoneAlways(_ enabled: Bool) {
        permissionDefaults.askForCameraAndMicrophoneAlways = enabled
        sitePermissionsStore.savePermissionDefaults(permissionDefaults)
    }

    func setTrackerBlockingMode(_ mode: TrackerBlockingMode) {
        contentBlockerService.setMode(mode)
    }

    func setEnableWebInspectorInDebugBuilds(_ enabled: Bool) {
        sessionSettings.enableWebInspectorInDebugBuilds = enabled
        sessionStore.saveSettings(sessionSettings)
        applyInspectablePreferenceToAllWebViews()
    }

    func setEnableWebInspectorInReleaseBuilds(_ enabled: Bool) {
        sessionSettings.enableWebInspectorInReleaseBuilds = enabled
        sessionStore.saveSettings(sessionSettings)
        applyInspectablePreferenceToAllWebViews()
    }

    func viewSourceForSelectedTab() {
        guard let urlString = selectedPageURLString(),
              let url = URL(string: urlString),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return
        }
        _ = newTab(urlString: "view-source:\(url.absoluteString)", shouldSelect: true, shouldLoad: true)
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

    func shouldAllowPermissionRequest(
        type: SitePermissionType,
        host: String?,
        completion: @escaping (Bool) -> Void
    ) {
        guard let host, !host.isEmpty else {
            completion(false)
            return
        }

        let resolved = permissionValue(for: type, host: host)
        if resolved == .block {
            completion(false)
            return
        }

        let shouldAlwaysAskCameraMic = permissionDefaults.askForCameraAndMicrophoneAlways &&
            (type == .camera || type == .microphone)

        if resolved == .allow, !shouldAlwaysAskCameraMic {
            completion(true)
            return
        }

        presentPermissionPrompt(for: type, host: host, completion: completion)
    }

    func clearWebsiteData(for host: String, completion: (() -> Void)? = nil) {
        guard let selectedTabID else {
            completion?()
            return
        }
        let webView = webView(for: selectedTabID)
        let dataStore = webView.configuration.websiteDataStore
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
            let loweredHost = host.lowercased()
            let matchingRecords = records.filter { record in
                let displayName = record.displayName.lowercased()
                return displayName == loweredHost || displayName.contains(loweredHost) || loweredHost.contains(displayName)
            }
            dataStore.removeData(ofTypes: dataTypes, for: matchingRecords) {
                completion?()
            }
        }
    }

    func webView(for tabID: UUID) -> WKWebView {
        if let webView = webViews[tabID] {
            applyStoredPageSettings(for: tabID, in: webView)
            return webView
        }

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        contentBlockerService.apply(to: configuration.userContentController)
        if let tab = tabs.first(where: { $0.id == tabID }), tab.isPrivate {
            configuration.websiteDataStore = .nonPersistent()
        } else if let tab = tabs.first(where: { $0.id == tabID }) {
            configuration.websiteDataStore = profileStore.websiteDataStore(for: tab.profileID)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = shouldEnableWebInspector()
        webViews[tabID] = webView
        attachObservers(to: webView, tabID: tabID)
        applyStoredPageSettings(for: tabID, in: webView)
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

    func zoomInSelectedTab() {
        adjustZoomForSelectedTab(delta: 0.1)
    }

    func zoomOutSelectedTab() {
        adjustZoomForSelectedTab(delta: -0.1)
    }

    func resetZoomSelectedTab() {
        guard let selectedTabID else { return }
        setZoomFactor(1.0, for: selectedTabID)
    }

    func toggleReaderModeForSelectedTab() {
        guard let selectedTabID, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        tabs[index].isReaderModeEnabled.toggle()
        applyReaderModeIfNeeded(for: selectedTabID)
    }

    func syncTabState(from webView: WKWebView, for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let previousHost = host(from: tabs[index].urlString)

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

        let currentHost = host(from: tabs[index].urlString)
        if currentHost != previousHost {
            if let currentHost, let cachedData = faviconCacheByHost[currentHost] {
                tabs[index].faviconData = cachedData
            } else {
                tabs[index].faviconData = nil
            }
        }
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

    func refreshFavicon(for tabID: UUID, from webView: WKWebView) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard let pageURL = webView.url else { return }
        guard let host = pageURL.host?.lowercased(), !host.isEmpty else { return }

        if let cachedData = faviconCacheByHost[host] {
            tabs[index].faviconData = cachedData
            return
        }

        faviconTasks[tabID]?.cancel()

        resolveIconURLFromDOM(webView: webView, pageURL: pageURL) { [weak self] domIconURL in
            guard let self else { return }

            let fallbackURL = self.faviconFallbackURL(for: pageURL)
            var candidates: [URL] = []
            if let domIconURL {
                candidates.append(domIconURL)
            }
            if let fallbackURL {
                candidates.append(fallbackURL)
            }

            self.fetchFirstValidFavicon(for: tabID, host: host, candidates: candidates)
        }
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

    private func adjustZoomForSelectedTab(delta: Double) {
        guard let selectedTabID else { return }
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let target = tabs[index].zoomFactor + delta
        setZoomFactor(target, for: selectedTabID)
    }

    private func setZoomFactor(_ value: Double, for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let clamped = min(max(value, 0.5), 3.0)
        tabs[index].zoomFactor = clamped
        webViews[tabID]?.pageZoom = clamped
    }

    private func applyReaderModeIfNeeded(for tabID: UUID) {
        guard let webView = webViews[tabID] else { return }
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        setReaderMode(in: webView, enabled: tab.isReaderModeEnabled)
    }

    private func resolveIconURLFromDOM(webView: WKWebView, pageURL: URL, completion: @escaping (URL?) -> Void) {
        let script = """
        (() => {
          const selectors = [
            'link[rel~="apple-touch-icon"]',
            'link[rel~="apple-touch-icon-precomposed"]',
            'link[rel~="icon"]',
            'link[rel="shortcut icon"]'
          ];
          for (const selector of selectors) {
            const element = document.querySelector(selector);
            if (element && element.href) {
              return element.href;
            }
          }
          return null;
        })();
        """

        webView.evaluateJavaScript(script) { value, _ in
            guard let iconURLString = value as? String, !iconURLString.isEmpty else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            if let directURL = URL(string: iconURLString) {
                DispatchQueue.main.async {
                    completion(directURL)
                }
                return
            }

            DispatchQueue.main.async {
                completion(URL(string: iconURLString, relativeTo: pageURL)?.absoluteURL)
            }
        }
    }

    private func fetchFirstValidFavicon(for tabID: UUID, host: String, candidates: [URL]) {
        guard !candidates.isEmpty else { return }
        let firstCandidate = candidates[0]
        fetchFavicon(at: firstCandidate, for: tabID, host: host) { [weak self] success in
            guard let self else { return }
            guard !success else { return }
            self.fetchFirstValidFavicon(
                for: tabID,
                host: host,
                candidates: Array(candidates.dropFirst())
            )
        }
    }

    private func fetchFavicon(at url: URL, for tabID: UUID, host: String, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            DispatchQueue.main.async {
                self.faviconTasks[tabID] = nil
            }

            guard error == nil else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            guard
                let response = response as? HTTPURLResponse,
                (200..<400).contains(response.statusCode),
                let data,
                !data.isEmpty
            else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            let mimeType = response.mimeType?.lowercased() ?? ""
            guard mimeType.hasPrefix("image/") || mimeType.contains("icon") else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            DispatchQueue.main.async {
                self.faviconCacheByHost[host] = data
                if let index = self.tabs.firstIndex(where: { $0.id == tabID }) {
                    self.tabs[index].faviconData = data
                }
                completion(true)
            }
        }

        faviconTasks[tabID] = task
        task.resume()
    }

    private func faviconFallbackURL(for pageURL: URL) -> URL? {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: true) else {
            return nil
        }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func host(from urlString: String) -> String? {
        URL(string: urlString)?.host?.lowercased()
    }

    private func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func defaultPermissionValue(for type: SitePermissionType) -> SitePermissionValue {
        if type == .popups, permissionDefaults.blockPopupsByDefault {
            return .block
        }
        return .ask
    }

    private func presentPermissionPrompt(
        for type: SitePermissionType,
        host: String,
        completion: @escaping (Bool) -> Void
    ) {
        let runPrompt = {
            let alert = NSAlert()
            alert.messageText = self.permissionPromptTitle(for: type)
            alert.informativeText = "\(host) wants to use \(type.title.lowercased())."
            alert.addButton(withTitle: "Allow Once")
            alert.addButton(withTitle: "Allow Always")
            alert.addButton(withTitle: "Block")
            alert.alertStyle = .informational

            let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
                switch response {
                case .alertFirstButtonReturn:
                    completion(true)
                case .alertSecondButtonReturn:
                    self.setPermissionValue(.allow, for: type, host: host)
                    completion(true)
                default:
                    self.setPermissionValue(.block, for: type, host: host)
                    completion(false)
                }
            }

            if let keyWindow = NSApp.keyWindow {
                alert.beginSheetModal(for: keyWindow, completionHandler: handleResponse)
            } else {
                handleResponse(alert.runModal())
            }
        }

        if Thread.isMainThread {
            runPrompt()
        } else {
            DispatchQueue.main.async(execute: runPrompt)
        }
    }

    private func permissionPromptTitle(for type: SitePermissionType) -> String {
        switch type {
        case .camera:
            return "Allow Camera Access?"
        case .microphone:
            return "Allow Microphone Access?"
        case .location:
            return "Allow Location Access?"
        case .notifications:
            return "Allow Notifications?"
        case .popups:
            return "Allow Pop-up Window?"
        }
    }

    private func persistSession() {
        guard sessionSettings.restorePreviousSession else { return }
        let now = Date()
        let persistedTabs = tabs.map { tab in
            let shouldPersistPrivateURL = sessionSettings.includePrivateTabsInSession || !tab.isPrivate
            let persistedURL = shouldPersistPrivateURL ? tab.urlString : "about:blank"
            let persistedTitle = shouldPersistPrivateURL ? tab.title : nil
            let selectedAt = (tab.id == selectedTabID) ? now : tab.lastSelectedAt

            return PersistedTab(
                id: tab.id,
                profileID: tab.profileID,
                urlString: persistedURL,
                title: persistedTitle,
                isPinned: tab.isPinned,
                isPrivate: tab.isPrivate,
                lastSelectedAt: selectedAt
            )
        }

        let snapshot = BrowserSessionSnapshot(
            tabs: persistedTabs,
            selectedTabID: selectedTabID,
            savedAt: now
        )
        sessionStore.saveSession(snapshot)
    }

    private func pushClosedTabState(for tab: Tab) {
        let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "New Tab" : title
        closedTabsStack.append(
            ClosedTabState(
                profileID: tab.profileID,
                urlString: tab.urlString,
                title: displayTitle,
                isPrivate: tab.isPrivate,
                isPinned: tab.isPinned
            )
        )
    }

    private func setSelectedTabID(_ id: UUID?) {
        selectedTabID = id
        guard let id, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].lastSelectedAt = Date()
    }

    private func setReaderMode(in webView: WKWebView, enabled: Bool) {
        let script: String
        if enabled {
            script = """
            (() => {
              try {
                const id = 'pine-reader-mode-lite';
                const hasPasswordField = !!document.querySelector('input[type="password"]');
                if (hasPasswordField) {
                  const existing = document.getElementById(id);
                  if (existing) {
                    existing.remove();
                  }
                  return;
                }
                let style = document.getElementById(id);
                if (!style) {
                  style = document.createElement('style');
                  style.id = id;
                  document.head.appendChild(style);
                }
                style.textContent = `
                  html, body {
                    max-width: 760px !important;
                    margin: 0 auto !important;
                    padding: 0 16px !important;
                    font-size: 19px !important;
                    line-height: 1.7 !important;
                    word-break: break-word !important;
                  }
                  img, video, iframe, table, pre {
                    max-width: 100% !important;
                  }
                  pre, code {
                    font-size: 0.9em !important;
                    line-height: 1.5 !important;
                  }
                `;
              } catch (_) {}
            })();
            """
        } else {
            script = """
            (() => {
              try {
                const style = document.getElementById('pine-reader-mode-lite');
                if (style) {
                  style.remove();
                }
              } catch (_) {}
            })();
            """
        }

        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func applyStoredPageSettings(for tabID: UUID, in webView: WKWebView) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        webView.pageZoom = tab.zoomFactor
        setReaderMode(in: webView, enabled: tab.isReaderModeEnabled)
    }

    private func normalizePinnedOrdering() {
        let pinnedTabs = tabs.filter(\.isPinned)
        let unpinnedTabs = tabs.filter { !$0.isPinned }
        tabs = pinnedTabs + unpinnedTabs
    }

    private func applyContentBlockingToAllWebViews() {
        for webView in webViews.values {
            contentBlockerService.apply(to: webView.configuration.userContentController)
        }
    }

    private func applyInspectablePreferenceToAllWebViews() {
        let enabled = shouldEnableWebInspector()
        for webView in webViews.values {
            webView.isInspectable = enabled
        }
    }

    private func shouldEnableWebInspector() -> Bool {
#if DEBUG
        return sessionSettings.enableWebInspectorInDebugBuilds
#else
        return sessionSettings.enableWebInspectorInReleaseBuilds
#endif
    }

    private func cleanedURLStringConservatively(_ input: String) -> String? {
        guard let url = URL(string: input), var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return nil
        }
        guard let queryItems = components.queryItems, !queryItems.isEmpty else {
            return input
        }

        let knownTrackingKeys: Set<String> = ["fbclid", "gclid"]
        let filtered = queryItems.filter { item in
            let key = item.name.lowercased()
            if key.hasPrefix("utm_") {
                return false
            }
            if knownTrackingKeys.contains(key) {
                return false
            }
            return true
        }

        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.url?.absoluteString ?? input
    }
}
