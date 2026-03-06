import Foundation

final class SharedStores {
    static let shared = SharedStores()

    let historyStore: HistoryStore
    let bookmarksStore: BookmarksStore
    let downloadManager: DownloadManager

    private init() {
        historyStore = HistoryStore()
        bookmarksStore = BookmarksStore()
        downloadManager = DownloadManager()
    }
}
