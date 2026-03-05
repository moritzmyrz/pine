import Foundation

struct Tab: Identifiable {
    let id: UUID
    var urlString: String
    var title: String
    var isLoading: Bool
    var estimatedProgress: Double
    var canGoBack: Bool
    var canGoForward: Bool

    init(
        id: UUID = UUID(),
        urlString: String,
        title: String = "New Tab",
        isLoading: Bool = false,
        estimatedProgress: Double = 0,
        canGoBack: Bool = false,
        canGoForward: Bool = false
    ) {
        self.id = id
        self.urlString = urlString
        self.title = title
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }
}
