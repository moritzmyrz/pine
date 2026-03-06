import Foundation
import WebKit

final class ProfileStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let profilesFileURL: URL
    private let profileStorageDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var websiteDataStoresByProfileID: [UUID: WKWebsiteDataStore] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directoryURL = appSupport.appendingPathComponent("pine", isDirectory: true)
        profilesFileURL = directoryURL.appendingPathComponent("profiles.json")
        profileStorageDirectoryURL = directoryURL.appendingPathComponent("profile-storage", isDirectory: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    func loadProfiles() -> [Profile] {
        guard let data = try? Data(contentsOf: profilesFileURL),
              let decoded = try? decoder.decode([Profile].self, from: data) else {
            return [Profile(name: "Default", isDefault: true)]
        }

        let nonEmpty = decoded.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmpty.isEmpty else {
            return [Profile(name: "Default", isDefault: true)]
        }

        var normalized = nonEmpty
        if !normalized.contains(where: \.isDefault) {
            normalized[0].isDefault = true
        }

        let defaultCount = normalized.filter(\.isDefault).count
        if defaultCount > 1 {
            var didKeepFirstDefault = false
            for index in normalized.indices {
                if normalized[index].isDefault {
                    if didKeepFirstDefault {
                        normalized[index].isDefault = false
                    } else {
                        didKeepFirstDefault = true
                    }
                }
            }
        }

        return normalized
    }

    func saveProfiles(_ profiles: [Profile]) {
        do {
            try createDirectoryIfNeeded()
            let data = try encoder.encode(profiles)
            try data.write(to: profilesFileURL, options: .atomic)
        } catch {
            return
        }
    }

    func websiteDataStore(for profileID: UUID) -> WKWebsiteDataStore {
        if let cached = websiteDataStoresByProfileID[profileID] {
            return cached
        }

        if let identified = identifiedWebsiteDataStore(for: profileID) {
            websiteDataStoresByProfileID[profileID] = identified
            return identified
        }

        return .default()
    }

    func deleteStoredWebsiteData(for profileID: UUID, completion: @escaping () -> Void) {
        try? fileManager.removeItem(at: profileStorageDirectoryURL.appendingPathComponent(profileID.uuidString, isDirectory: true))
        websiteDataStoresByProfileID[profileID] = nil

        guard let dataStore = identifiedWebsiteDataStore(for: profileID) else {
            completion()
            return
        }
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
            dataStore.removeData(ofTypes: dataTypes, for: records) {
                completion()
            }
        }
    }

    private func identifiedWebsiteDataStore(for profileID: UUID) -> WKWebsiteDataStore? {
        let selector = NSSelectorFromString("dataStoreForIdentifier:")
        let classObject: AnyObject = WKWebsiteDataStore.self
        guard classObject.responds(to: selector),
              let unmanagedStore = classObject.perform(selector, with: profileID as NSUUID),
              let store = unmanagedStore.takeUnretainedValue() as? WKWebsiteDataStore else {
            return nil
        }
        return store
    }

    private func createDirectoryIfNeeded() throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: profileStorageDirectoryURL.path) {
            try fileManager.createDirectory(at: profileStorageDirectoryURL, withIntermediateDirectories: true)
        }
    }
}
