import Combine
import Foundation

struct HistoryEntry: Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let urlString: String

    init(id: UUID = UUID(), date: Date = Date(), title: String, urlString: String) {
        self.id = id
        self.date = date
        self.title = title
        self.urlString = urlString
    }
}

final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    func addEntry(title: String, urlString: String) {
        let normalizedURL = normalized(urlString: urlString)

        if let latest = entries.first,
           normalized(urlString: latest.urlString) == normalizedURL {
            return
        }

        let displayTitle = title.isEmpty ? urlString : title
        let entry = HistoryEntry(title: displayTitle, urlString: urlString)
        entries.insert(entry, at: 0)
    }

    private func normalized(urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }

        components.fragment = nil
        return components.string ?? urlString
    }
}
