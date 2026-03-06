import Combine
import Foundation

struct BookmarkFolder: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let parentID: UUID?

    init(id: UUID = UUID(), name: String, parentID: UUID? = nil) {
        self.id = id
        self.name = name
        self.parentID = parentID
    }
}

struct Bookmark: Identifiable, Codable {
    let id: UUID
    let title: String
    let urlString: String
    let createdAt: Date
    let folderID: UUID?
    let folderName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case urlString
        case createdAt
        case folderID
        case folderName
    }

    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        createdAt: Date = Date(),
        folderID: UUID? = nil,
        folderName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
        self.folderID = folderID
        self.folderName = folderName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        urlString = try container.decode(String.self, forKey: .urlString)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        folderName = try container.decodeIfPresent(String.self, forKey: .folderName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

final class BookmarksStore: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var folders: [BookmarkFolder] = []

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let folderStorageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "pine.bookmarks.v1",
        folderStorageKey: String = "pine.bookmarkFolders.v1"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.folderStorageKey = folderStorageKey
        load()
    }

    func bookmark(forURLString urlString: String) -> Bookmark? {
        guard let normalized = normalizedURLString(from: urlString) else { return nil }
        return bookmarks.first { normalizedURLString(from: $0.urlString) == normalized }
    }

    func addBookmark(title: String, urlString: String) {
        addBookmark(title: title, urlString: urlString, folderID: nil)
    }

    func addBookmark(title: String, urlString: String, folderID: UUID?) {
        guard let normalized = normalizedURLString(from: urlString) else { return }
        guard bookmark(forURLString: normalized) == nil else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? normalized : trimmedTitle
        let bookmark = Bookmark(title: displayTitle, urlString: normalized, folderID: folderID)
        bookmarks.insert(bookmark, at: 0)
        save()
    }

    func removeBookmark(urlString: String) {
        guard let normalized = normalizedURLString(from: urlString) else { return }
        bookmarks.removeAll { normalizedURLString(from: $0.urlString) == normalized }
        save()
    }

    func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    func renameBookmark(id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        let existing = bookmarks[index]
        bookmarks[index] = Bookmark(
            id: existing.id,
            title: trimmed,
            urlString: existing.urlString,
            createdAt: existing.createdAt,
            folderID: existing.folderID
        )
        save()
    }

    func moveBookmark(id: UUID, toFolderID folderID: UUID?) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        if let folderID, !folders.contains(where: { $0.id == folderID }) {
            return
        }

        let existing = bookmarks[index]
        bookmarks[index] = Bookmark(
            id: existing.id,
            title: existing.title,
            urlString: existing.urlString,
            createdAt: existing.createdAt,
            folderID: folderID
        )
        save()
    }

    @discardableResult
    func addFolder(named folderName: String, parentID: UUID? = nil) -> UUID? {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let existing = folders.first(where: {
            $0.parentID == parentID && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return existing.id
        }

        let folder = BookmarkFolder(name: trimmed, parentID: parentID)
        folders.append(folder)
        sortFolders()
        saveFolders()
        return folder.id
    }

    func renameFolder(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }

        let parentID = folders[index].parentID
        let hasConflict = folders.contains {
            $0.id != id && $0.parentID == parentID && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !hasConflict else { return }

        folders[index] = BookmarkFolder(id: id, name: trimmed, parentID: parentID)
        sortFolders()
        saveFolders()
    }

    func deleteFolder(id: UUID) {
        let removedIDs = Set([id] + folderDescendantIDs(of: id))
        folders.removeAll { removedIDs.contains($0.id) }
        bookmarks.removeAll { bookmark in
            guard let folderID = bookmark.folderID else { return false }
            return removedIDs.contains(folderID)
        }
        save()
    }

    func moveFolder(id: UUID, toParentID parentID: UUID?) {
        guard id != parentID else { return }
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        if let parentID, folderDescendantIDs(of: id).contains(parentID) {
            return
        }

        let name = folders[index].name
        let hasConflict = folders.contains {
            $0.id != id && $0.parentID == parentID && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        guard !hasConflict else { return }

        folders[index] = BookmarkFolder(id: id, name: name, parentID: parentID)
        sortFolders()
        saveFolders()
    }

    func rootFolders() -> [BookmarkFolder] {
        childFolders(of: nil)
    }

    func childFolders(of parentID: UUID?) -> [BookmarkFolder] {
        folders.filter { $0.parentID == parentID }
    }

    func bookmarks(in folderID: UUID?) -> [Bookmark] {
        bookmarks
            .filter { $0.folderID == folderID }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func folderPath(for folderID: UUID?) -> String {
        guard let folderID else { return "Unsorted" }
        var names: [String] = []
        var currentID: UUID? = folderID
        while let id = currentID, let folder = folders.first(where: { $0.id == id }) {
            names.insert(folder.name, at: 0)
            currentID = folder.parentID
        }
        return names.isEmpty ? "Unsorted" : names.joined(separator: "/")
    }

    var folderNames: [String] {
        folders.map(\.name)
    }

    func toggleBookmark(title: String, urlString: String) {
        if bookmark(forURLString: urlString) != nil {
            removeBookmark(urlString: urlString)
        } else {
            addBookmark(title: title, urlString: urlString)
        }
    }

    private func load() {
        loadFolders()

        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? decoder.decode([Bookmark].self, from: data) {
            bookmarks = decoded
        } else {
            bookmarks = []
        }

        migrateLegacyFolderNamesIfNeeded()
    }

    private func save() {
        do {
            let data = try encoder.encode(bookmarks)
            userDefaults.set(data, forKey: storageKey)
            saveFolders()
        } catch {
            return
        }
    }

    private func saveFolders() {
        do {
            let data = try encoder.encode(folders)
            userDefaults.set(data, forKey: folderStorageKey)
        } catch {
            return
        }
    }

    private func loadFolders() {
        if let data = userDefaults.data(forKey: folderStorageKey),
           let decoded = try? decoder.decode([BookmarkFolder].self, from: data) {
            folders = decoded
            sortFolders()
            return
        }

        if let oldFolderNames = userDefaults.stringArray(forKey: folderStorageKey) {
            folders = oldFolderNames.map { BookmarkFolder(name: $0, parentID: nil) }
            sortFolders()
            saveFolders()
            return
        }

        folders = []
    }

    private func sortFolders() {
        folders.sort { lhs, rhs in
            if lhs.parentID == rhs.parentID {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return (lhs.parentID?.uuidString ?? "") < (rhs.parentID?.uuidString ?? "")
        }
    }

    private func folderDescendantIDs(of folderID: UUID) -> [UUID] {
        let children = folders.filter { $0.parentID == folderID }.map(\.id)
        return children + children.flatMap { folderDescendantIDs(of: $0) }
    }

    private func migrateLegacyFolderNamesIfNeeded() {
        var changed = false
        var migrated: [Bookmark] = []

        for bookmark in bookmarks {
            if bookmark.folderID != nil || bookmark.folderName == nil {
                migrated.append(bookmark)
                continue
            }

            let segments = (bookmark.folderName ?? "")
                .split(separator: "/")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var parentID: UUID?
            for segment in segments {
                parentID = addFolder(named: segment, parentID: parentID)
            }

            migrated.append(
                Bookmark(
                    id: bookmark.id,
                    title: bookmark.title,
                    urlString: bookmark.urlString,
                    createdAt: bookmark.createdAt,
                    folderID: parentID
                )
            )
            changed = true
        }

        if changed {
            bookmarks = migrated
            save()
        }
    }

    private func normalizedURLString(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let resolvedURL: URL
        if let directURL = URL(string: trimmed), directURL.scheme != nil {
            resolvedURL = directURL
        } else if !trimmed.contains(" "), trimmed.contains("."), let httpsURL = URL(string: "https://\(trimmed)") {
            resolvedURL = httpsURL
        } else {
            return nil
        }

        guard var components = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.fragment = nil
        return components.url?.absoluteString ?? resolvedURL.absoluteString
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
