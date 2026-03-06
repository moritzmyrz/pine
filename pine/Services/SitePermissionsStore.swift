import Foundation

enum SitePermissionType: String, CaseIterable, Identifiable, Codable {
    case camera
    case microphone
    case location
    case notifications
    case popups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera:
            return "Camera"
        case .microphone:
            return "Microphone"
        case .location:
            return "Location"
        case .notifications:
            return "Notifications"
        case .popups:
            return "Pop-ups"
        }
    }
}

enum SitePermissionValue: String, CaseIterable, Codable, Hashable {
    case ask
    case allow
    case block

    var title: String {
        switch self {
        case .ask:
            return "Ask"
        case .allow:
            return "Allow"
        case .block:
            return "Block"
        }
    }
}

struct SitePermissionEntry: Codable {
    var camera: SitePermissionValue
    var microphone: SitePermissionValue
    var location: SitePermissionValue
    var notifications: SitePermissionValue
    var popups: SitePermissionValue

    static let `default` = SitePermissionEntry(
        camera: .ask,
        microphone: .ask,
        location: .ask,
        notifications: .ask,
        popups: .ask
    )

    func value(for type: SitePermissionType) -> SitePermissionValue {
        switch type {
        case .camera:
            return camera
        case .microphone:
            return microphone
        case .location:
            return location
        case .notifications:
            return notifications
        case .popups:
            return popups
        }
    }

    mutating func setValue(_ value: SitePermissionValue, for type: SitePermissionType) {
        switch type {
        case .camera:
            camera = value
        case .microphone:
            microphone = value
        case .location:
            location = value
        case .notifications:
            notifications = value
        case .popups:
            popups = value
        }
    }
}

struct PermissionDefaults: Codable {
    var blockPopupsByDefault: Bool
    var askForCameraAndMicrophoneAlways: Bool

    static let `default` = PermissionDefaults(
        blockPopupsByDefault: true,
        askForCameraAndMicrophoneAlways: true
    )
}

final class SitePermissionsStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let sitePermissionsFileURL: URL
    private let permissionDefaultsFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directoryURL = appSupport.appendingPathComponent("pine", isDirectory: true)
        sitePermissionsFileURL = directoryURL.appendingPathComponent("site-permissions.json")
        permissionDefaultsFileURL = directoryURL.appendingPathComponent("permission-defaults.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func loadSitePermissions() -> [String: SitePermissionEntry] {
        guard let data = try? Data(contentsOf: sitePermissionsFileURL),
              let decoded = try? decoder.decode([String: SitePermissionEntry].self, from: data) else {
            return [:]
        }
        return decoded
    }

    func saveSitePermissions(_ permissionsByHost: [String: SitePermissionEntry]) {
        do {
            try createDirectoryIfNeeded()
            let data = try encoder.encode(permissionsByHost)
            try data.write(to: sitePermissionsFileURL, options: .atomic)
        } catch {
            return
        }
    }

    func loadPermissionDefaults() -> PermissionDefaults {
        guard let data = try? Data(contentsOf: permissionDefaultsFileURL),
              let defaults = try? decoder.decode(PermissionDefaults.self, from: data) else {
            return .default
        }
        return defaults
    }

    func savePermissionDefaults(_ defaults: PermissionDefaults) {
        do {
            try createDirectoryIfNeeded()
            let data = try encoder.encode(defaults)
            try data.write(to: permissionDefaultsFileURL, options: .atomic)
        } catch {
            return
        }
    }

    private func createDirectoryIfNeeded() throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
}
