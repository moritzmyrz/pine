import Foundation

final class WorkspaceController {
    private let store: BrowserStore
    private let workspaceStore: WorkspaceStore
    private let tabManager: TabManager
    private let sessionStore: SessionStore

    init(
        store: BrowserStore,
        workspaceStore: WorkspaceStore,
        tabManager: TabManager,
        sessionStore: SessionStore
    ) {
        self.store = store
        self.workspaceStore = workspaceStore
        self.tabManager = tabManager
        self.sessionStore = sessionStore
    }

    func loadWorkspaces() {
        let persisted = workspaceStore.loadState()
        store.workspaces = persisted.workspaces
        if let currentWorkspaceID = persisted.currentWorkspaceID,
           persisted.workspaces.contains(where: { $0.id == currentWorkspaceID }) {
            store.currentWorkspaceID = currentWorkspaceID
        } else {
            store.currentWorkspaceID = nil
        }
    }

    @discardableResult
    func createWorkspaceFromCurrentTabs(named name: String?) -> UUID? {
        let (pinnedSnapshots, tabSnapshots) = currentWorkspaceSnapshots()
        guard !pinnedSnapshots.isEmpty || !tabSnapshots.isEmpty else {
            return nil
        }

        let trimmedName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let workspaceName = trimmedName.isEmpty ? "Workspace \(store.workspaces.count + 1)" : trimmedName
        let workspace = Workspace(
            name: workspaceName,
            tabSnapshots: tabSnapshots,
            pinnedSnapshots: pinnedSnapshots
        )

        store.workspaces.append(workspace)
        store.currentWorkspaceID = workspace.id
        persist()
        return workspace.id
    }

    func switchToWorkspace(id: UUID) {
        guard let workspace = store.workspaces.first(where: { $0.id == id }) else { return }

        let pinnedTabs = workspace.pinnedSnapshots.map { snapshot in
            Tab(
                profileID: resolvedProfileID(for: snapshot.profileID),
                urlString: snapshot.urlString,
                title: resolvedTitle(snapshot.title),
                isPrivate: false,
                isPinned: true
            )
        }
        let regularTabs = workspace.tabSnapshots.map { snapshot in
            Tab(
                profileID: resolvedProfileID(for: snapshot.profileID),
                urlString: snapshot.urlString,
                title: resolvedTitle(snapshot.title),
                isPrivate: false,
                isPinned: false
            )
        }
        tabManager.replaceAllTabs(with: pinnedTabs + regularTabs, selectedTabID: nil)

        if let profileID = store.selectedTab?.profileID {
            store.currentProfileID = profileID
            store.sessionSettings.currentProfileID = profileID
            sessionStore.saveSettings(store.sessionSettings)
        }

        store.currentWorkspaceID = workspace.id
        persist()
    }

    func renameWorkspace(id: UUID, to newName: String) {
        guard let index = store.workspaces.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.workspaces[index].name = trimmed
        persist()
    }

    func deleteWorkspace(id: UUID) {
        guard let index = store.workspaces.firstIndex(where: { $0.id == id }) else { return }
        store.workspaces.remove(at: index)
        if store.currentWorkspaceID == id {
            store.currentWorkspaceID = nil
        }
        persist()
    }

    var hasSavableTabs: Bool {
        store.tabs.contains(where: { !$0.isPrivate })
    }

    private func currentWorkspaceSnapshots() -> ([WorkspaceTabSnapshot], [WorkspaceTabSnapshot]) {
        let nonPrivateTabs = store.tabs.filter { !$0.isPrivate }
        let pinned = nonPrivateTabs
            .filter(\.isPinned)
            .map { tab in
                WorkspaceTabSnapshot(
                    profileID: tab.profileID,
                    urlString: tab.urlString,
                    title: resolvedTitle(tab.title)
                )
            }
        let regular = nonPrivateTabs
            .filter { !$0.isPinned }
            .map { tab in
                WorkspaceTabSnapshot(
                    profileID: tab.profileID,
                    urlString: tab.urlString,
                    title: resolvedTitle(tab.title)
                )
            }
        return (pinned, regular)
    }

    private func persist() {
        workspaceStore.saveState(workspaces: store.workspaces, currentWorkspaceID: store.currentWorkspaceID)
    }

    private func resolvedProfileID(for profileID: UUID) -> UUID {
        if store.profiles.contains(where: { $0.id == profileID }) {
            return profileID
        }
        return store.currentProfileID
    }

    private func resolvedTitle(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Tab" : trimmed
    }
}
