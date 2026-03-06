import Combine
import Foundation

enum SplitLayout {
    case vertical
}

enum ActivePane {
    case primary
    case secondary
}

final class BrowserStore: ObservableObject {
    static let minSplitRatio: CGFloat = 0.2
    static let maxSplitRatio: CGFloat = 0.8

    @Published var tabs: [Tab] = []
    @Published var selectedTabID: UUID?
    @Published var isSplitViewEnabled = false
    @Published var splitSecondaryTabID: UUID?
    @Published var splitLayout: SplitLayout = .vertical
    @Published var activePane: ActivePane = .primary
    @Published var splitRatio: CGFloat = 0.5

    @Published var profiles: [Profile] = []
    @Published var currentProfileID: UUID = UUID()
    @Published var workspaces: [Workspace] = []
    @Published var currentWorkspaceID: UUID?

    @Published var sessionSettings: BrowserSettings = .default
    @Published var permissionDefaults: PermissionDefaults = .default
    @Published var trackerBlockingMode: TrackerBlockingMode = .off

    @Published var addressBarFocusToken = UUID()
    @Published private(set) var shouldSelectAllInAddressBar = false

    @Published var isHistoryPresented = false
    @Published var isBookmarksPresented = false
    @Published var isDownloadsPresented = false
    @Published var isSettingsPresented = false
    @Published var isProfileManagementPresented = false
    @Published var isCommandPalettePresented = false
    @Published var isTabSearchPresented = false
    @Published var tabSearchQuery = ""

    @Published var isDownloadsShelfDismissed = false
    @Published var profilePendingDeletion: Profile?

    var selectedTab: Tab? {
        guard let selectedTabID else { return nil }
        return tabs.first(where: { $0.id == selectedTabID })
    }

    var splitPrimaryTabID: UUID? {
        selectedTabID
    }

    var sortedTabs: [Tab] {
        tabs
    }

    var currentProfile: Profile? {
        profiles.first(where: { $0.id == currentProfileID })
    }

    func requestAddressBarFocus(selectAll: Bool = false) {
        shouldSelectAllInAddressBar = selectAll
        addressBarFocusToken = UUID()
    }

    func consumeAddressBarSelectAllRequest() {
        shouldSelectAllInAddressBar = false
    }

    func setSelectedTabID(_ id: UUID?) {
        selectedTabID = id
        guard let id, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].lastSelectedAt = Date()
    }

    func normalizePinnedOrdering() {
        let pinnedTabs = tabs.filter(\.isPinned)
        let unpinnedTabs = tabs.filter { !$0.isPinned }
        tabs = pinnedTabs + unpinnedTabs
    }

    func setSplitRatio(_ value: CGFloat) {
        splitRatio = min(max(value, Self.minSplitRatio), Self.maxSplitRatio)
    }
}
