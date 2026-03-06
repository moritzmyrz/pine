import Combine
import Foundation

final class DownloadController {
    let downloadManager: DownloadManager

    private let store: BrowserStore
    private var cancellables: Set<AnyCancellable> = []

    init(store: BrowserStore, downloadManager: DownloadManager) {
        self.store = store
        self.downloadManager = downloadManager
        bindDownloadState()
    }

    var shouldShowShelf: Bool {
        if hasActiveDownloads {
            return true
        }
        if store.isDownloadsShelfDismissed {
            return false
        }
        return !downloadManager.shelfItems.isEmpty
    }

    func showDownloadsSheet() {
        store.isDownloadsPresented = true
    }

    func dismissShelf() {
        store.isDownloadsShelfDismissed = true
    }

    private var hasActiveDownloads: Bool {
        downloadManager.items.contains { item in
            item.status == .downloading || item.status == .pending || item.status == .paused
        }
    }

    private func bindDownloadState() {
        downloadManager.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // Keep shelf visible while active transfers run, even if user dismissed it.
                if self.hasActiveDownloads {
                    self.store.isDownloadsShelfDismissed = false
                }
            }
            .store(in: &cancellables)
    }
}
