import Foundation

final class ProfileManager {
    private let store: BrowserStore
    private let profileStore: ProfileStore
    private let sessionStore: SessionStore
    private let tabManager: TabManager

    var onProfileDeleted: (() -> Void)?

    init(
        store: BrowserStore,
        profileStore: ProfileStore,
        sessionStore: SessionStore,
        tabManager: TabManager
    ) {
        self.store = store
        self.profileStore = profileStore
        self.sessionStore = sessionStore
        self.tabManager = tabManager
    }

    func loadProfiles() {
        store.profiles = profileStore.loadProfiles()
    }

    func profileName(for profileID: UUID) -> String {
        store.profiles.first(where: { $0.id == profileID })?.name ?? "Unknown"
    }

    func selectProfile(id: UUID) {
        guard store.profiles.contains(where: { $0.id == id }) else { return }
        store.currentProfileID = id
        store.sessionSettings.currentProfileID = id
        sessionStore.saveSettings(store.sessionSettings)

        if let currentSelectedID = store.selectedTabID,
           store.tabs.first(where: { $0.id == currentSelectedID })?.profileID == id {
            return
        }

        if let existing = store.tabs.last(where: { $0.profileID == id }) {
            store.setSelectedTabID(existing.id)
        } else {
            _ = tabManager.newBlankTab(shouldSelect: true, isPrivate: false)
        }
    }

    @discardableResult
    func createProfile(named name: String?) -> UUID {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = "Profile \(store.profiles.count + 1)"
        let profile = Profile(name: trimmed.isEmpty ? fallbackName : trimmed, isDefault: false)
        store.profiles.append(profile)
        profileStore.saveProfiles(store.profiles)
        return profile.id
    }

    func renameProfile(id: UUID, to newName: String) {
        guard let index = store.profiles.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.profiles[index].name = trimmed
        profileStore.saveProfiles(store.profiles)
    }

    func canDeleteProfile(id: UUID) -> Bool {
        guard let profile = store.profiles.first(where: { $0.id == id }) else { return false }
        if profile.isDefault {
            return false
        }
        return store.profiles.count > 1
    }

    func deleteProfile(id: UUID) {
        guard canDeleteProfile(id: id) else { return }

        tabManager.closeTabs(inProfileID: id)
        store.profiles.removeAll { $0.id == id }
        profileStore.saveProfiles(store.profiles)
        profileStore.deleteStoredWebsiteData(for: id) {}

        if store.currentProfileID == id {
            let fallbackProfileID = store.profiles.first(where: \.isDefault)?.id ?? store.profiles.first?.id
            if let fallbackProfileID {
                store.currentProfileID = fallbackProfileID
                store.sessionSettings.currentProfileID = fallbackProfileID
                sessionStore.saveSettings(store.sessionSettings)
            }
        }

        if let selectedTabID = store.selectedTabID, store.tabs.contains(where: { $0.id == selectedTabID }) {
            if let selectedTab = store.tabs.first(where: { $0.id == selectedTabID }),
               selectedTab.profileID != store.currentProfileID,
               let replacement = store.tabs.last(where: { $0.profileID == store.currentProfileID }) {
                store.setSelectedTabID(replacement.id)
            }
        } else if let replacement = store.tabs.last(where: { $0.profileID == store.currentProfileID }) {
            store.setSelectedTabID(replacement.id)
        } else {
            _ = tabManager.newBlankTab(shouldSelect: true, isPrivate: false)
        }

        onProfileDeleted?()
    }
}
