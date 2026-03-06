import Foundation

enum LayoutStyle: String, Codable, CaseIterable, Identifiable {
    case topBar
    case sidebar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topBar:
            return "Top Bar"
        case .sidebar:
            return "Sidebar"
        }
    }
}

struct PersistedTab: Codable {
    let id: UUID
    let profileID: UUID?
    let urlString: String
    let title: String?
    let isPinned: Bool
    let isPrivate: Bool
    let lastSelectedAt: Date?
}

struct BrowserSessionSnapshot: Codable {
    let tabs: [PersistedTab]
    let selectedTabID: UUID?
    let isSplitViewEnabled: Bool
    let splitSecondaryTabID: UUID?
    let activePaneRawValue: String
    let splitRatio: Double
    let savedAt: Date

    private enum CodingKeys: String, CodingKey {
        case tabs
        case selectedTabID
        case isSplitViewEnabled
        case splitSecondaryTabID
        case activePaneRawValue
        case splitRatio
        case savedAt
    }

    init(
        tabs: [PersistedTab],
        selectedTabID: UUID?,
        isSplitViewEnabled: Bool,
        splitSecondaryTabID: UUID?,
        activePaneRawValue: String,
        splitRatio: Double,
        savedAt: Date
    ) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.isSplitViewEnabled = isSplitViewEnabled
        self.splitSecondaryTabID = splitSecondaryTabID
        self.activePaneRawValue = activePaneRawValue
        self.splitRatio = splitRatio
        self.savedAt = savedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try container.decode([PersistedTab].self, forKey: .tabs)
        selectedTabID = try container.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        isSplitViewEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSplitViewEnabled) ?? false
        splitSecondaryTabID = try container.decodeIfPresent(UUID.self, forKey: .splitSecondaryTabID)
        activePaneRawValue = try container.decodeIfPresent(String.self, forKey: .activePaneRawValue) ?? "primary"
        splitRatio = try container.decodeIfPresent(Double.self, forKey: .splitRatio) ?? 0.5
        savedAt = try container.decode(Date.self, forKey: .savedAt)
    }
}

struct BrowserSettings: Codable {
    var restorePreviousSession: Bool
    var includePrivateTabsInSession: Bool
    var showCompactTabStrip: Bool
    var layoutStyle: LayoutStyle
    var showBookmarksBar: Bool
    var zenModeHidesToolbar: Bool
    var zenModeKeepsSidebar: Bool
    var escExitsZenMode: Bool
    var hideHTTPSInAddressBar: Bool
    var hideWWWInAddressBar: Bool
    var alwaysShowFullURLInAddressBar: Bool
    var currentProfileID: UUID?
    var enableWebInspectorInDebugBuilds: Bool
    var enableWebInspectorInReleaseBuilds: Bool

    static let `default` = BrowserSettings(
        restorePreviousSession: true,
        includePrivateTabsInSession: false,
        showCompactTabStrip: true,
        layoutStyle: .topBar,
        showBookmarksBar: true,
        zenModeHidesToolbar: true,
        zenModeKeepsSidebar: false,
        escExitsZenMode: true,
        hideHTTPSInAddressBar: true,
        hideWWWInAddressBar: true,
        alwaysShowFullURLInAddressBar: false,
        currentProfileID: nil,
        enableWebInspectorInDebugBuilds: true,
        enableWebInspectorInReleaseBuilds: false
    )

    private enum CodingKeys: String, CodingKey {
        case restorePreviousSession
        case includePrivateTabsInSession
        case showCompactTabStrip
        case layoutStyle
        case showBookmarksBar
        case zenModeHidesToolbar
        case zenModeKeepsSidebar
        case escExitsZenMode
        case hideHTTPSInAddressBar
        case hideWWWInAddressBar
        case alwaysShowFullURLInAddressBar
        case currentProfileID
        case enableWebInspectorInDebugBuilds
        case enableWebInspectorInReleaseBuilds
    }

    init(
        restorePreviousSession: Bool,
        includePrivateTabsInSession: Bool,
        showCompactTabStrip: Bool,
        layoutStyle: LayoutStyle,
        showBookmarksBar: Bool,
        zenModeHidesToolbar: Bool,
        zenModeKeepsSidebar: Bool,
        escExitsZenMode: Bool,
        hideHTTPSInAddressBar: Bool,
        hideWWWInAddressBar: Bool,
        alwaysShowFullURLInAddressBar: Bool,
        currentProfileID: UUID?,
        enableWebInspectorInDebugBuilds: Bool,
        enableWebInspectorInReleaseBuilds: Bool
    ) {
        self.restorePreviousSession = restorePreviousSession
        self.includePrivateTabsInSession = includePrivateTabsInSession
        self.showCompactTabStrip = showCompactTabStrip
        self.layoutStyle = layoutStyle
        self.showBookmarksBar = showBookmarksBar
        self.zenModeHidesToolbar = zenModeHidesToolbar
        self.zenModeKeepsSidebar = zenModeKeepsSidebar
        self.escExitsZenMode = escExitsZenMode
        self.hideHTTPSInAddressBar = hideHTTPSInAddressBar
        self.hideWWWInAddressBar = hideWWWInAddressBar
        self.alwaysShowFullURLInAddressBar = alwaysShowFullURLInAddressBar
        self.currentProfileID = currentProfileID
        self.enableWebInspectorInDebugBuilds = enableWebInspectorInDebugBuilds
        self.enableWebInspectorInReleaseBuilds = enableWebInspectorInReleaseBuilds
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        restorePreviousSession = try container.decodeIfPresent(Bool.self, forKey: .restorePreviousSession) ?? true
        includePrivateTabsInSession = try container.decodeIfPresent(Bool.self, forKey: .includePrivateTabsInSession) ?? false
        showCompactTabStrip = try container.decodeIfPresent(Bool.self, forKey: .showCompactTabStrip) ?? true
        layoutStyle = try container.decodeIfPresent(LayoutStyle.self, forKey: .layoutStyle) ?? .topBar
        showBookmarksBar = try container.decodeIfPresent(Bool.self, forKey: .showBookmarksBar) ?? true
        zenModeHidesToolbar = try container.decodeIfPresent(Bool.self, forKey: .zenModeHidesToolbar) ?? true
        zenModeKeepsSidebar = try container.decodeIfPresent(Bool.self, forKey: .zenModeKeepsSidebar) ?? false
        escExitsZenMode = try container.decodeIfPresent(Bool.self, forKey: .escExitsZenMode) ?? true
        hideHTTPSInAddressBar = try container.decodeIfPresent(Bool.self, forKey: .hideHTTPSInAddressBar) ?? true
        hideWWWInAddressBar = try container.decodeIfPresent(Bool.self, forKey: .hideWWWInAddressBar) ?? true
        alwaysShowFullURLInAddressBar =
            try container.decodeIfPresent(Bool.self, forKey: .alwaysShowFullURLInAddressBar) ?? false
        currentProfileID = try container.decodeIfPresent(UUID.self, forKey: .currentProfileID)
        enableWebInspectorInDebugBuilds =
            try container.decodeIfPresent(Bool.self, forKey: .enableWebInspectorInDebugBuilds) ?? true
        enableWebInspectorInReleaseBuilds =
            try container.decodeIfPresent(Bool.self, forKey: .enableWebInspectorInReleaseBuilds) ?? false
    }
}

final class SessionStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let sessionFileURL: URL
    private let settingsFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directoryURL = appSupport.appendingPathComponent("pine", isDirectory: true)
        sessionFileURL = directoryURL.appendingPathComponent("session.json")
        settingsFileURL = directoryURL.appendingPathComponent("settings.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadSettings() -> BrowserSettings {
        guard let data = try? Data(contentsOf: settingsFileURL) else {
            return .default
        }
        return (try? decoder.decode(BrowserSettings.self, from: data)) ?? .default
    }

    func saveSettings(_ settings: BrowserSettings) {
        do {
            try createDirectoryIfNeeded()
            let data = try encoder.encode(settings)
            try data.write(to: settingsFileURL, options: .atomic)
        } catch {
            return
        }
    }

    func loadSession() -> BrowserSessionSnapshot? {
        guard let data = try? Data(contentsOf: sessionFileURL) else {
            return nil
        }
        return try? decoder.decode(BrowserSessionSnapshot.self, from: data)
    }

    func saveSession(_ snapshot: BrowserSessionSnapshot) {
        do {
            try createDirectoryIfNeeded()
            let data = try encoder.encode(snapshot)
            try data.write(to: sessionFileURL, options: .atomic)
        } catch {
            return
        }
    }

    func clearSession() {
        try? fileManager.removeItem(at: sessionFileURL)
    }

    private func createDirectoryIfNeeded() throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
}
