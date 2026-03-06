import Foundation

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
    let savedAt: Date
}

struct BrowserSettings: Codable {
    var restorePreviousSession: Bool
    var includePrivateTabsInSession: Bool
    var showCompactTabStrip: Bool
    var currentProfileID: UUID?
    var enableWebInspectorInDebugBuilds: Bool
    var enableWebInspectorInReleaseBuilds: Bool

    static let `default` = BrowserSettings(
        restorePreviousSession: true,
        includePrivateTabsInSession: false,
        showCompactTabStrip: true,
        currentProfileID: nil,
        enableWebInspectorInDebugBuilds: true,
        enableWebInspectorInReleaseBuilds: false
    )

    private enum CodingKeys: String, CodingKey {
        case restorePreviousSession
        case includePrivateTabsInSession
        case showCompactTabStrip
        case currentProfileID
        case enableWebInspectorInDebugBuilds
        case enableWebInspectorInReleaseBuilds
    }

    init(
        restorePreviousSession: Bool,
        includePrivateTabsInSession: Bool,
        showCompactTabStrip: Bool,
        currentProfileID: UUID?,
        enableWebInspectorInDebugBuilds: Bool,
        enableWebInspectorInReleaseBuilds: Bool
    ) {
        self.restorePreviousSession = restorePreviousSession
        self.includePrivateTabsInSession = includePrivateTabsInSession
        self.showCompactTabStrip = showCompactTabStrip
        self.currentProfileID = currentProfileID
        self.enableWebInspectorInDebugBuilds = enableWebInspectorInDebugBuilds
        self.enableWebInspectorInReleaseBuilds = enableWebInspectorInReleaseBuilds
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        restorePreviousSession = try container.decodeIfPresent(Bool.self, forKey: .restorePreviousSession) ?? true
        includePrivateTabsInSession = try container.decodeIfPresent(Bool.self, forKey: .includePrivateTabsInSession) ?? false
        showCompactTabStrip = try container.decodeIfPresent(Bool.self, forKey: .showCompactTabStrip) ?? true
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
