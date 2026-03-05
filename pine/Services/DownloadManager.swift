import AppKit
import Combine
import Foundation
import WebKit

struct DownloadItem: Identifiable {
    enum Status: String {
        case pending
        case downloading
        case completed
        case failed
        case cancelled
    }

    let id: UUID
    var filename: String
    var destination: URL?
    var progress: Double
    var status: Status
    var errorDescription: String?

    init(
        id: UUID = UUID(),
        filename: String,
        destination: URL? = nil,
        progress: Double = 0,
        status: Status = .pending,
        errorDescription: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.destination = destination
        self.progress = progress
        self.status = status
        self.errorDescription = errorDescription
    }
}

final class DownloadManager: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []

    private struct DownloadContext {
        let itemID: UUID
        let progressObservation: NSKeyValueObservation
    }

    private var contexts: [ObjectIdentifier: DownloadContext] = [:]

    func track(download: WKDownload, suggestedFilename: String) {
        let item = DownloadItem(filename: safeFilename(from: suggestedFilename), status: .pending)
        items.insert(item, at: 0)

        let key = ObjectIdentifier(download)
        let observation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            self?.updateProgress(for: key, progress: progress.fractionCompleted)
        }
        contexts[key] = DownloadContext(itemID: item.id, progressObservation: observation)
    }

    func chooseDestination(suggestedFilename: String, completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.title = "Save Download"
        panel.nameFieldStringValue = safeFilename(from: suggestedFilename)
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }

    func didChooseDestination(for download: WKDownload, destination: URL?) {
        let key = ObjectIdentifier(download)
        guard let itemID = contexts[key]?.itemID else { return }

        updateItem(id: itemID) { item in
            item.destination = destination
            if destination == nil {
                item.status = .cancelled
            } else {
                item.status = .downloading
            }
        }
    }

    func didFinish(download: WKDownload) {
        let key = ObjectIdentifier(download)
        guard let context = contexts[key] else { return }

        updateItem(id: context.itemID) { item in
            item.progress = 1
            item.status = .completed
        }
        context.progressObservation.invalidate()
        contexts[key] = nil
    }

    func didFail(download: WKDownload, error: Error) {
        let key = ObjectIdentifier(download)
        guard let context = contexts[key] else { return }

        updateItem(id: context.itemID) { item in
            item.status = .failed
            item.errorDescription = error.localizedDescription
        }
        context.progressObservation.invalidate()
        contexts[key] = nil
    }

    private func updateProgress(for key: ObjectIdentifier, progress: Double) {
        guard let itemID = contexts[key]?.itemID else { return }

        updateItem(id: itemID) { item in
            item.progress = max(0, min(1, progress))
            if item.status == .pending {
                item.status = .downloading
            }
        }
    }

    private func updateItem(id: UUID, _ update: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        update(&item)
        items[index] = item
    }

    private func safeFilename(from suggestedFilename: String) -> String {
        let trimmed = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "download" : trimmed
    }
}
