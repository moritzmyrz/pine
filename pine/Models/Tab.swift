import Foundation

struct Tab: Identifiable {
    let id: UUID
    var urlString: String
    var title: String

    init(id: UUID = UUID(), urlString: String, title: String = "New Tab") {
        self.id = id
        self.urlString = urlString
        self.title = title
    }
}
