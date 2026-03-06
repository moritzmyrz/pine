import Combine
import Foundation

struct Bookmark: Identifiable, Codable {
    let id: UUID
    let title: String
    let urlString: String
    let createdAt: Date
    let folderName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case urlString
        case createdAt
        case folderName
    }

    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        createdAt: Date = Date(),
        folderName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
        self.folderName = folderName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        urlString = try container.decode(String.self, forKey: .urlString)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        folderName = try container.decodeIfPresent(String.self, forKey: .folderName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

final class BookmarksStore: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var folders: [String] = []

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
        addBookmark(title: title, urlString: urlString, folderName: nil)
    }

    func addBookmark(title: String, urlString: String, folderName: String?) {
        guard let normalized = normalizedURLString(from: urlString) else { return }
        guard bookmark(forURLString: normalized) == nil else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? normalized : trimmedTitle

        let bookmark = Bookmark(title: displayTitle, urlString: normalized, folderName: folderName)
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

    func setFolderName(_ folderName: String?, for bookmarkID: UUID) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        if let folderName {
            addFolder(named: folderName)
        }
        let existing = bookmarks[index]
        bookmarks[index] = Bookmark(
            id: existing.id,
            title: existing.title,
            urlString: existing.urlString,
            createdAt: existing.createdAt,
            folderName: folderName
        )
        save()
    }

    func addFolder(named folderName: String) {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !folders.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        folders.append(trimmed)
        folders.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        saveFolders()
    }

    var folderNames: [String] {
        let bookmarkFolders = Set(bookmarks.compactMap(\.folderName))
        return Array(bookmarkFolders.union(Set(folders)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func toggleBookmark(title: String, urlString: String) {
        if bookmark(forURLString: urlString) != nil {
            removeBookmark(urlString: urlString)
        } else {
            addBookmark(title: title, urlString: urlString)
        }
    }

    private func load() {
        if let data = userDefaults.data(forKey: storageKey) {
            do {
                bookmarks = try decoder.decode([Bookmark].self, from: data)
            } catch {
                bookmarks = []
            }
        } else {
            bookmarks = []
        }

        folders = userDefaults.stringArray(forKey: folderStorageKey) ?? []
        folders.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
        userDefaults.set(folders, forKey: folderStorageKey)
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
