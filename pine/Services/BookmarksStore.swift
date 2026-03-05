import Combine
import Foundation

struct Bookmark: Identifiable, Codable {
    let id: UUID
    let title: String
    let urlString: String
    let createdAt: Date

    init(id: UUID = UUID(), title: String, urlString: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
    }
}

final class BookmarksStore: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "pine.bookmarks.v1"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        load()
    }

    func bookmark(forURLString urlString: String) -> Bookmark? {
        guard let normalized = normalizedURLString(from: urlString) else { return nil }
        return bookmarks.first { normalizedURLString(from: $0.urlString) == normalized }
    }

    func addBookmark(title: String, urlString: String) {
        guard let normalized = normalizedURLString(from: urlString) else { return }
        guard bookmark(forURLString: normalized) == nil else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? normalized : trimmedTitle

        let bookmark = Bookmark(title: displayTitle, urlString: normalized)
        bookmarks.insert(bookmark, at: 0)
        save()
    }

    func removeBookmark(urlString: String) {
        guard let normalized = normalizedURLString(from: urlString) else { return }

        bookmarks.removeAll { normalizedURLString(from: $0.urlString) == normalized }
        save()
    }

    func toggleBookmark(title: String, urlString: String) {
        if bookmark(forURLString: urlString) != nil {
            removeBookmark(urlString: urlString)
        } else {
            addBookmark(title: title, urlString: urlString)
        }
    }

    private func load() {
        guard let data = userDefaults.data(forKey: storageKey) else {
            bookmarks = []
            return
        }

        do {
            bookmarks = try decoder.decode([Bookmark].self, from: data)
        } catch {
            bookmarks = []
        }
    }

    private func save() {
        do {
            let data = try encoder.encode(bookmarks)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            return
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
