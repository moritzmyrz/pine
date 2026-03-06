import Foundation

struct Tab: Identifiable {
    let id: UUID
    var profileID: UUID
    var urlString: String
    var title: String
    var isPrivate: Bool
    var isPinned: Bool
    var zoomFactor: Double
    var isReaderModeEnabled: Bool
    var lastSelectedAt: Date?
    var faviconData: Data?
    var isLoading: Bool
    var estimatedProgress: Double
    var canGoBack: Bool
    var canGoForward: Bool

    init(
        id: UUID = UUID(),
        profileID: UUID,
        urlString: String,
        title: String = "New Tab",
        isPrivate: Bool = false,
        isPinned: Bool = false,
        zoomFactor: Double = 1.0,
        isReaderModeEnabled: Bool = false,
        lastSelectedAt: Date? = nil,
        faviconData: Data? = nil,
        isLoading: Bool = false,
        estimatedProgress: Double = 0,
        canGoBack: Bool = false,
        canGoForward: Bool = false
    ) {
        self.id = id
        self.profileID = profileID
        self.urlString = urlString
        self.title = title
        self.isPrivate = isPrivate
        self.isPinned = isPinned
        self.zoomFactor = zoomFactor
        self.isReaderModeEnabled = isReaderModeEnabled
        self.lastSelectedAt = lastSelectedAt
        self.faviconData = faviconData
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }
}
