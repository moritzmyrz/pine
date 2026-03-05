import Foundation

struct Tab: Identifiable {
    let id: UUID
    var urlString: String
    var title: String
    var isPrivate: Bool
    var isLoading: Bool
    var estimatedProgress: Double
    var canGoBack: Bool
    var canGoForward: Bool

    init(
        id: UUID = UUID(),
        urlString: String,
        title: String = "New Tab",
        isPrivate: Bool = false,
        isLoading: Bool = false,
        estimatedProgress: Double = 0,
        canGoBack: Bool = false,
        canGoForward: Bool = false
    ) {
        self.id = id
        self.urlString = urlString
        self.title = title
        self.isPrivate = isPrivate
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }
}
