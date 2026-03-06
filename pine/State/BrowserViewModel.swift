import AppKit
import Combine
import Foundation
import WebKit

final class BrowserViewModel: ObservableObject {
    let store: BrowserStore
    let tabManager: TabManager
    let navigationController: NavigationController
    let sessionManager: SessionManager
    let profileManager: ProfileManager
    let workspaceController: WorkspaceController
    let downloadController: DownloadController
    let permissionController: PermissionController
    let commandRegistry: CommandRegistry

    let historyStore: HistoryStore
    let bookmarksStore: BookmarksStore
    let downloadManager: DownloadManager
    let sessionStore: SessionStore
    let profileStore: ProfileStore
    let workspaceStore: WorkspaceStore
    let sitePermissionsStore: SitePermissionsStore
    let contentBlockerService: ContentBlockerService

    private var cancellables: Set<AnyCancellable> = []

    var tabs: [Tab] { store.tabs }
    var selectedTabID: UUID? { store.selectedTabID }
    var isSplitViewEnabled: Bool { store.isSplitViewEnabled }
    var splitSecondaryTabID: UUID? { store.splitSecondaryTabID }
    var splitPrimaryTabID: UUID? { store.splitPrimaryTabID }
    var activePane: ActivePane { store.activePane }
    var splitRatio: CGFloat { store.splitRatio }
    var profiles: [Profile] { store.profiles }
    var currentProfileID: UUID { store.currentProfileID }
    var workspaces: [Workspace] { store.workspaces }
    var currentWorkspaceID: UUID? { store.currentWorkspaceID }
    var sessionSettings: BrowserSettings { store.sessionSettings }
    var permissionDefaults: PermissionDefaults { store.permissionDefaults }
    var trackerBlockingMode: TrackerBlockingMode { store.trackerBlockingMode }
    var addressBarFocusToken: UUID { store.addressBarFocusToken }
    var shouldSelectAllInAddressBar: Bool { store.shouldSelectAllInAddressBar }
    var selectedTab: Tab? { store.selectedTab }
    var activeTab: Tab? {
        guard let activeID = activeNavigationTabID else { return store.selectedTab }
        return store.tabs.first(where: { $0.id == activeID })
    }
    var sortedTabs: [Tab] { store.sortedTabs }
    var currentProfile: Profile? { store.currentProfile }

    init(
        historyStore: HistoryStore = HistoryStore(),
        bookmarksStore: BookmarksStore = BookmarksStore(),
        downloadManager: DownloadManager = DownloadManager(),
        sessionStore: SessionStore = SessionStore(),
        profileStore: ProfileStore = ProfileStore(),
        workspaceStore: WorkspaceStore = WorkspaceStore(),
        sitePermissionsStore: SitePermissionsStore = SitePermissionsStore(),
        contentBlockerService: ContentBlockerService = ContentBlockerService()
    ) {
        self.historyStore = historyStore
        self.bookmarksStore = bookmarksStore
        self.downloadManager = downloadManager
        self.sessionStore = sessionStore
        self.profileStore = profileStore
        self.workspaceStore = workspaceStore
        self.sitePermissionsStore = sitePermissionsStore
        self.contentBlockerService = contentBlockerService

        let store = BrowserStore()
        self.store = store

        let tabManager = TabManager(store: store)
        self.tabManager = tabManager

        let downloadController = DownloadController(store: store, downloadManager: downloadManager)
        self.downloadController = downloadController

        let permissionController = PermissionController(
            store: store,
            sitePermissionsStore: sitePermissionsStore,
            contentBlockerService: contentBlockerService
        )
        self.permissionController = permissionController

        let sessionManager = SessionManager(store: store, sessionStore: sessionStore)
        self.sessionManager = sessionManager

        let profileManager = ProfileManager(
            store: store,
            profileStore: profileStore,
            sessionStore: sessionStore,
            tabManager: tabManager
        )
        self.profileManager = profileManager

        let workspaceController = WorkspaceController(
            store: store,
            workspaceStore: workspaceStore,
            tabManager: tabManager,
            sessionStore: sessionStore
        )
        self.workspaceController = workspaceController

        let navigationController = NavigationController(
            store: store,
            historyStore: historyStore,
            bookmarksStore: bookmarksStore,
            profileStore: profileStore,
            sessionStore: sessionStore,
            contentBlockerService: contentBlockerService,
            tabManager: tabManager,
            downloadController: downloadController
        )
        self.navigationController = navigationController
        let commandRegistry = CommandRegistry()
        self.commandRegistry = commandRegistry

        registerDefaultPaletteCommands()
        bind()
        loadInitialState()
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
        tabManager.newTab(
            urlString: urlString,
            shouldSelect: shouldSelect,
            shouldLoad: shouldLoad,
            focusAddressBar: focusAddressBar,
            isPrivate: isPrivate,
            profileID: profileID
        )
    }

    @discardableResult
    func newBlankTab(shouldSelect: Bool = true, isPrivate: Bool = false) -> UUID {
        tabManager.newBlankTab(shouldSelect: shouldSelect, isPrivate: isPrivate)
    }

    @discardableResult
    func newPrivateTab(urlString: String = "https://example.com", focusAddressBar: Bool = false) -> UUID {
        tabManager.newPrivateTab(urlString: urlString, focusAddressBar: focusAddressBar)
    }

    func closeTab(id: UUID) { tabManager.closeTab(id: id) }
    func duplicateTab(id: UUID) { tabManager.duplicateTab(id: id) }
    func closeOtherTabs(keeping id: UUID) { tabManager.closeOtherTabs(keeping: id) }
    func closeTabsToRight(of id: UUID) { tabManager.closeTabsToRight(of: id) }
    func setTabPinned(id: UUID, isPinned: Bool) { tabManager.setTabPinned(id: id, isPinned: isPinned) }
    func reorderTab(draggedID: UUID, before targetID: UUID) { tabManager.reorderTab(draggedID: draggedID, before: targetID) }
    func selectTab(atOneBasedIndex index: Int) { tabManager.selectTab(atOneBasedIndex: index) }
    func cycleTab(forward: Bool) { tabManager.cycleTab(forward: forward) }
    func closeCurrentTab() { tabManager.closeCurrentTab() }
    func reopenClosedTab() { tabManager.reopenClosedTab() }
    func selectTab(id: UUID) { tabManager.selectTab(id: id) }
    func toggleSplitView() { tabManager.toggleSplitView() }
    func enableSplitView(withSecondaryTabID secondaryTabID: UUID) { tabManager.enableSplitView(withSecondaryTabID: secondaryTabID) }
    func disableSplitView() { tabManager.disableSplitView() }
    func setSecondaryTab(id: UUID?) { tabManager.setSecondaryTab(id: id) }
    func swapSplitPanes() { tabManager.swapSplitPanes() }
    func setActivePane(_ pane: ActivePane) { tabManager.setActivePane(pane) }
    func switchActivePane(forward: Bool) { tabManager.switchActivePane(forward: forward) }
    func setSplitRatio(_ ratio: CGFloat) { tabManager.setSplitRatio(ratio) }
    func resetSplitRatio() { tabManager.resetSplitRatio() }

    func tabsMatching(query: String) -> [Tab] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return store.tabs }
        let lowered = trimmedQuery.lowercased()
        return store.tabs.filter { tab in
            tab.title.lowercased().contains(lowered) || tab.urlString.lowercased().contains(lowered)
        }
    }

    func searchPaletteCommands(query: String) -> [PaletteItem] {
        commandRegistry.search(query: query)
    }

    func profileName(for profileID: UUID) -> String { profileManager.profileName(for: profileID) }
    func setRestorePreviousSessionEnabled(_ enabled: Bool) { sessionManager.setRestorePreviousSessionEnabled(enabled) }
    func setIncludePrivateTabsInSession(_ enabled: Bool) { sessionManager.setIncludePrivateTabsInSession(enabled) }
    func setShowCompactTabStrip(_ enabled: Bool) { sessionManager.setShowCompactTabStrip(enabled) }
    var hasSavableTabsForWorkspace: Bool { workspaceController.hasSavableTabs }
    @discardableResult
    func createWorkspaceFromCurrentTabs(named name: String?) -> UUID? {
        workspaceController.createWorkspaceFromCurrentTabs(named: name)
    }
    func switchToWorkspace(id: UUID) {
        workspaceController.switchToWorkspace(id: id)
        sessionManager.persistSession()
    }
    func renameWorkspace(id: UUID, to newName: String) { workspaceController.renameWorkspace(id: id, to: newName) }
    func deleteWorkspace(id: UUID) { workspaceController.deleteWorkspace(id: id) }
    func selectProfile(id: UUID) { profileManager.selectProfile(id: id) }
    @discardableResult func createProfile(named name: String?) -> UUID { profileManager.createProfile(named: name) }
    func renameProfile(id: UUID, to newName: String) { profileManager.renameProfile(id: id, to: newName) }
    func canDeleteProfile(id: UUID) -> Bool { profileManager.canDeleteProfile(id: id) }
    func deleteProfile(id: UUID) { profileManager.deleteProfile(id: id) }

    func openInNewTab(request: URLRequest?, fromTabID: UUID?) {
        navigationController.openInNewTab(request: request, fromTabID: fromTabID)
    }

    func requestAddressBarFocus(selectAll: Bool = false) { store.requestAddressBarFocus(selectAll: selectAll) }
    func consumeAddressBarSelectAllRequest() { store.consumeAddressBarSelectAllRequest() }
    func currentSiteHost() -> String? { permissionController.currentSiteHost() }
    func permissionValue(for type: SitePermissionType, host: String) -> SitePermissionValue { permissionController.permissionValue(for: type, host: host) }
    func setPermissionValue(_ value: SitePermissionValue, for type: SitePermissionType, host: String) { permissionController.setPermissionValue(value, for: type, host: host) }
    func setBlockPopupsByDefault(_ enabled: Bool) { permissionController.setBlockPopupsByDefault(enabled) }
    func setAskCameraAndMicrophoneAlways(_ enabled: Bool) { permissionController.setAskCameraAndMicrophoneAlways(enabled) }
    func setTrackerBlockingMode(_ mode: TrackerBlockingMode) { permissionController.setTrackerBlockingMode(mode) }
    func setEnableWebInspectorInDebugBuilds(_ enabled: Bool) { navigationController.setEnableWebInspectorInDebugBuilds(enabled) }
    func setEnableWebInspectorInReleaseBuilds(_ enabled: Bool) { navigationController.setEnableWebInspectorInReleaseBuilds(enabled) }

    func viewSourceForSelectedTab() { navigationController.viewSourceForSelectedTab() }
    func openSelectedPageInSafari() { navigationController.openSelectedPageInSafari() }
    func copyCleanLinkForSelectedTab() { navigationController.copyCleanLinkForSelectedTab() }
    func showDownloads() { downloadController.showDownloadsSheet() }
    func showHistory() { store.isHistoryPresented = true }
    func showBookmarks() { store.isBookmarksPresented = true }
    func showSettings() { store.isSettingsPresented = true }

    func shouldAllowPermissionRequest(type: SitePermissionType, host: String?, completion: @escaping (Bool) -> Void) {
        permissionController.shouldAllowPermissionRequest(type: type, host: host, completion: completion)
    }

    func clearWebsiteData(for host: String, completion: (() -> Void)? = nil) {
        permissionController.clearWebsiteData(
            for: host,
            selectedTabID: store.selectedTabID,
            webViewProvider: { [navigationController] tabID in
                navigationController.webView(for: tabID)
            },
            completion: completion
        )
    }

    func webView(for tabID: UUID) -> WKWebView { navigationController.webView(for: tabID) }
    func loadSelectedTab() {
        guard let activeTabID = activeNavigationTabID else { return }
        navigationController.loadURL(activeTabURLString(for: activeTabID), in: activeTabID)
    }
    func loadSelectedTab(from urlInput: String) {
        guard let activeTabID = activeNavigationTabID else { return }
        navigationController.loadTab(tabID: activeTabID, from: urlInput)
    }
    func goBackSelectedTab() {
        guard let activeTabID = activeNavigationTabID else { return }
        navigationController.goBack(tabID: activeTabID)
    }
    func goForwardSelectedTab() {
        guard let activeTabID = activeNavigationTabID else { return }
        navigationController.goForward(tabID: activeTabID)
    }
    func reloadSelectedTab() {
        guard let activeTabID = activeNavigationTabID else { return }
        navigationController.reload(tabID: activeTabID)
    }
    func stopLoadingSelectedTab() {
        guard let activeTabID = activeNavigationTabID else { return }
        navigationController.stopLoading(tabID: activeTabID)
    }
    func zoomInSelectedTab() { navigationController.zoomInSelectedTab() }
    func zoomOutSelectedTab() { navigationController.zoomOutSelectedTab() }
    func resetZoomSelectedTab() { navigationController.resetZoomSelectedTab() }
    func toggleReaderModeForSelectedTab() { navigationController.toggleReaderModeForSelectedTab() }
    func syncTabState(from webView: WKWebView, for tabID: UUID) { navigationController.syncTabState(from: webView, for: tabID) }
    func recordHistoryForCompletedNavigation(tabID: UUID) { navigationController.recordHistoryForCompletedNavigation(tabID: tabID) }
    func loadHistoryEntryInSelectedTab(_ entry: HistoryEntry) { navigationController.loadHistoryEntryInSelectedTab(entry) }
    func loadBookmarkInSelectedTab(_ bookmark: Bookmark) { navigationController.loadBookmarkInSelectedTab(bookmark) }
    func isCurrentPageBookmarked() -> Bool { navigationController.isCurrentPageBookmarked() }
    func toggleBookmarkForSelectedTab() { navigationController.toggleBookmarkForSelectedTab() }
    func refreshFavicon(for tabID: UUID, from webView: WKWebView) { navigationController.refreshFavicon(for: tabID, from: webView) }
    func applyStoredPageSettings(for tabID: UUID, in webView: WKWebView) { navigationController.applyStoredPageSettings(for: tabID, in: webView) }

    private func bind() {
        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        bookmarksStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        tabManager.onTabRemoved = { [weak self] tabID in
            self?.navigationController.cleanupTabResources(tabID: tabID)
        }
        tabManager.onTabLoaded = { [weak self] tabID, urlString in
            self?.navigationController.loadURL(urlString, in: tabID)
        }
        profileManager.onProfileDeleted = { [weak self] in
            self?.sessionManager.persistSession()
        }

        contentBlockerService.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.permissionController.didReceiveTrackerModeChange(mode)
                self?.navigationController.applyContentBlockingToAllWebViews()
            }
            .store(in: &cancellables)

        contentBlockerService.onRuleListDidChange = { [weak self] in
            DispatchQueue.main.async {
                self?.navigationController.applyContentBlockingToAllWebViews()
            }
        }
    }

    private func registerDefaultPaletteCommands() {
        commandRegistry.setCommands([
            Command(
                id: "new-tab",
                title: "New Tab",
                subtitle: "Open a new tab",
                keywords: ["tab", "open", "create"],
                shortcutHint: "Cmd+T",
                group: "Commands"
            ) { [weak self] in
                self?.newTab(focusAddressBar: true)
            },
            Command(
                id: "new-private-tab",
                title: "New Private Tab",
                subtitle: "Open a private browsing tab",
                keywords: ["private", "incognito", "tab"],
                shortcutHint: "Cmd+Shift+N",
                group: "Commands"
            ) { [weak self] in
                self?.newPrivateTab(focusAddressBar: true)
            },
            Command(
                id: "toggle-split-view",
                title: "Toggle Split View",
                subtitle: "Enable or disable side-by-side tabs",
                keywords: ["split", "pane", "layout", "view"],
                shortcutHint: "Cmd+\\",
                group: "Commands"
            ) { [weak self] in
                self?.toggleSplitView()
            },
            Command(
                id: "show-downloads",
                title: "Show Downloads",
                subtitle: "Open the downloads sheet",
                keywords: ["downloads", "files", "transfer"],
                group: "Commands"
            ) { [weak self] in
                self?.showDownloads()
            },
            Command(
                id: "show-history",
                title: "Show History",
                subtitle: "Open browsing history",
                keywords: ["history", "visited", "pages"],
                shortcutHint: "Cmd+Y",
                group: "Commands"
            ) { [weak self] in
                self?.showHistory()
            },
            Command(
                id: "show-bookmarks",
                title: "Show Bookmarks",
                subtitle: "Open saved bookmarks",
                keywords: ["bookmarks", "saved", "favorites"],
                shortcutHint: "Cmd+Shift+B",
                group: "Commands"
            ) { [weak self] in
                self?.showBookmarks()
            },
            Command(
                id: "show-settings",
                title: "Settings",
                subtitle: "Open app settings",
                keywords: ["settings", "preferences", "options"],
                shortcutHint: "Cmd+,",
                group: "Commands"
            ) { [weak self] in
                self?.showSettings()
            }
        ])
    }

    private func loadInitialState() {
        sessionManager.applyInitialSettings()
        permissionController.loadInitialState()
        profileManager.loadProfiles()
        workspaceController.loadWorkspaces()

        let defaultProfileID = store.profiles.first(where: \.isDefault)?.id ?? store.profiles[0].id
        let savedProfileID = store.sessionSettings.currentProfileID
        let resolvedCurrentProfileID = savedProfileID.flatMap { candidate in
            store.profiles.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? defaultProfileID
        store.currentProfileID = resolvedCurrentProfileID

        let restored = sessionManager.restoreSessionIfNeeded(
            availableProfiles: store.profiles,
            resolvedCurrentProfileID: resolvedCurrentProfileID,
            onTabNeedsLoad: { [weak self] tabID, urlString in
                self?.navigationController.loadURL(urlString, in: tabID)
            }
        )
        if !restored {
            _ = tabManager.newTab(
                urlString: "https://example.com",
                shouldSelect: true,
                shouldLoad: true,
                isPrivate: false,
                profileID: resolvedCurrentProfileID
            )
        }

        store.sessionSettings.currentProfileID = resolvedCurrentProfileID
        sessionStore.saveSettings(store.sessionSettings)

        bindNotifications()
    }

    private func bindNotifications() {
        NotificationCenter.default.publisher(for: .pineNewTab)
            .sink { [weak self] _ in self?.newTab(focusAddressBar: true) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineNewPrivateTab)
            .sink { [weak self] _ in self?.newPrivateTab(focusAddressBar: true) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineCloseTab)
            .sink { [weak self] _ in self?.closeCurrentTab() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineReload)
            .sink { [weak self] _ in self?.reloadSelectedTab() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineGoBack)
            .sink { [weak self] _ in self?.goBackSelectedTab() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineGoForward)
            .sink { [weak self] _ in self?.goForwardSelectedTab() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineCycleTabsBackward)
            .sink { [weak self] _ in self?.cycleTab(forward: false) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineCycleTabsForward)
            .sink { [weak self] _ in self?.cycleTab(forward: true) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineSelectTabAtIndex)
            .sink { [weak self] notification in
                guard let index = notification.userInfo?["index"] as? Int else { return }
                self?.selectTab(atOneBasedIndex: index)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineReopenClosedTab)
            .sink { [weak self] _ in self?.reopenClosedTab() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineZoomIn)
            .sink { [weak self] _ in self?.zoomInSelectedTab() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineZoomOut)
            .sink { [weak self] _ in self?.zoomOutSelectedTab() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineZoomReset)
            .sink { [weak self] _ in self?.resetZoomSelectedTab() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineToggleReaderMode)
            .sink { [weak self] _ in self?.toggleReaderModeForSelectedTab() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineViewSource)
            .sink { [weak self] _ in self?.viewSourceForSelectedTab() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineOpenCurrentPageInSafari)
            .sink { [weak self] _ in self?.openSelectedPageInSafari() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineCopyCleanLink)
            .sink { [weak self] _ in self?.copyCleanLinkForSelectedTab() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineToggleSplitView)
            .sink { [weak self] _ in self?.toggleSplitView() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineSwitchActivePaneLeft)
            .sink { [weak self] _ in self?.switchActivePane(forward: false) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineSwitchActivePaneRight)
            .sink { [weak self] _ in self?.switchActivePane(forward: true) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineSwapSplitPanes)
            .sink { [weak self] _ in self?.swapSplitPanes() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .pineResetSplitDivider)
            .sink { [weak self] _ in self?.resetSplitRatio() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.sessionManager.persistSession() }
            .store(in: &cancellables)
        Timer.publish(every: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sessionManager.persistSession() }
            .store(in: &cancellables)
    }

    private var activeNavigationTabID: UUID? {
        if store.isSplitViewEnabled,
           store.activePane == .secondary,
           let secondaryID = store.splitSecondaryTabID,
           store.tabs.contains(where: { $0.id == secondaryID }) {
            return secondaryID
        }
        return store.selectedTabID
    }

    private func activeTabURLString(for tabID: UUID) -> String {
        store.tabs.first(where: { $0.id == tabID })?.urlString ?? ""
    }
}
