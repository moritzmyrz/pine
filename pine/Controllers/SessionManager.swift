import Foundation

final class SessionManager {
    private let store: BrowserStore
    private let sessionStore: SessionStore

    init(store: BrowserStore, sessionStore: SessionStore) {
        self.store = store
        self.sessionStore = sessionStore
    }

    func applyInitialSettings() {
        store.sessionSettings = sessionStore.loadSettings()
    }

    func restoreSessionIfNeeded(
        availableProfiles: [Profile],
        resolvedCurrentProfileID: UUID,
        onTabNeedsLoad: (UUID, String) -> Void
    ) -> Bool {
        guard store.sessionSettings.restorePreviousSession,
              let savedSession = sessionStore.loadSession(),
              !savedSession.tabs.isEmpty else {
            return false
        }

        store.tabs = savedSession.tabs.map { persisted in
            let restoredProfileID = persisted.profileID.flatMap { id in
                availableProfiles.contains(where: { $0.id == id }) ? id : nil
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
        store.normalizePinnedOrdering()
        if let selectedID = savedSession.selectedTabID, store.tabs.contains(where: { $0.id == selectedID }) {
            store.setSelectedTabID(selectedID)
        } else {
            store.setSelectedTabID(store.tabs.first?.id)
        }

        for tab in store.tabs {
            onTabNeedsLoad(tab.id, tab.urlString)
        }
        return true
    }

    func setRestorePreviousSessionEnabled(_ enabled: Bool) {
        store.sessionSettings.restorePreviousSession = enabled
        sessionStore.saveSettings(store.sessionSettings)
        if enabled {
            persistSession()
        } else {
            sessionStore.clearSession()
        }
    }

    func setIncludePrivateTabsInSession(_ enabled: Bool) {
        store.sessionSettings.includePrivateTabsInSession = enabled
        sessionStore.saveSettings(store.sessionSettings)
        persistSession()
    }

    func setShowCompactTabStrip(_ enabled: Bool) {
        store.sessionSettings.showCompactTabStrip = enabled
        sessionStore.saveSettings(store.sessionSettings)
    }

    func persistSession() {
        guard store.sessionSettings.restorePreviousSession else { return }
        let now = Date()
        let persistedTabs = store.tabs.map { tab in
            let shouldPersistPrivateURL = store.sessionSettings.includePrivateTabsInSession || !tab.isPrivate
            let persistedURL = shouldPersistPrivateURL ? tab.urlString : "about:blank"
            let persistedTitle = shouldPersistPrivateURL ? tab.title : nil
            let selectedAt = (tab.id == store.selectedTabID) ? now : tab.lastSelectedAt
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
            selectedTabID: store.selectedTabID,
            savedAt: now
        )
        sessionStore.saveSession(snapshot)
    }
}
