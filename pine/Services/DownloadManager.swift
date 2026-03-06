import AppKit
import Combine
import Foundation
import WebKit

struct DownloadItem: Identifiable {
    enum Status: String {
        case pending
        case downloading
        case paused
        case completed
        case failed
        case cancelled
    }

    let id: UUID
    var filename: String
    var sourceURL: URL?
    var destination: URL?
    var progress: Double
    var status: Status
    var errorDescription: String?
    var resumeData: Data?

    init(
        id: UUID = UUID(),
        filename: String,
        sourceURL: URL? = nil,
        destination: URL? = nil,
        progress: Double = 0,
        status: Status = .pending,
        errorDescription: String? = nil,
        resumeData: Data? = nil
    ) {
        self.id = id
        self.filename = filename
        self.sourceURL = sourceURL
        self.destination = destination
        self.progress = progress
        self.status = status
        self.errorDescription = errorDescription
        self.resumeData = resumeData
    }
}

final class DownloadManager: NSObject, ObservableObject {
    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var defaultDownloadFolder: URL
    @Published private(set) var askWhereToSaveEachFile: Bool

    private enum PendingFailureAction {
        case pause
        case cancel
    }

    private final class WeakWebViewBox {
        weak var webView: WKWebView?

        init(webView: WKWebView?) {
            self.webView = webView
        }
    }

    private struct WKDownloadContext {
        let itemID: UUID
        let download: WKDownload
        let progressObservation: NSKeyValueObservation
        let webViewBox: WeakWebViewBox
    }

    private struct RetryTaskContext {
        let itemID: UUID
        var destination: URL
        let sourceURL: URL
    }

    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let askWhereToSaveKey = "pine.download.askWhereToSaveEachFile"
    private let defaultFolderBookmarkKey = "pine.download.defaultFolderBookmark"

    private var wkContexts: [ObjectIdentifier: WKDownloadContext] = [:]
    private var pendingFailureActions: [ObjectIdentifier: PendingFailureAction] = [:]
    private var retryTasksByTaskID: [Int: RetryTaskContext] = [:]
    private var retryDownloadTasksByTaskID: [Int: URLSessionDownloadTask] = [:]
    private lazy var retrySession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()

    init(fileManager: FileManager = .default, userDefaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults

        let fallbackFolder = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        var bookmarkIsStale = false
        if let bookmarkData = userDefaults.data(forKey: defaultFolderBookmarkKey),
           let restoredURL = try? URL(
               resolvingBookmarkData: bookmarkData,
               options: [.withSecurityScope],
               relativeTo: nil,
               bookmarkDataIsStale: &bookmarkIsStale
           ) {
            defaultDownloadFolder = restoredURL
        } else {
            defaultDownloadFolder = fallbackFolder
        }
        askWhereToSaveEachFile = userDefaults.object(forKey: askWhereToSaveKey) as? Bool ?? true

        super.init()
    }

    var shelfItems: [DownloadItem] {
        Array(items.prefix(3))
    }

    var shouldShowShelf: Bool {
        let hasActive = items.contains { item in
            item.status == .downloading || item.status == .pending || item.status == .paused
        }
        if hasActive {
            return true
        }
        return !shelfItems.isEmpty
    }

    func setAskWhereToSaveEachFile(_ enabled: Bool) {
        askWhereToSaveEachFile = enabled
        userDefaults.set(enabled, forKey: askWhereToSaveKey)
    }

    func pickDefaultDownloadFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Default Download Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = defaultDownloadFolder

        panel.begin { [weak self] response in
            guard let self, response == .OK, let selected = panel.url else { return }
            self.setDefaultDownloadFolder(selected)
        }
    }

    func track(download: WKDownload, webView: WKWebView, suggestedFilename: String, sourceURL: URL?) {
        let item = DownloadItem(
            filename: safeFilename(from: suggestedFilename),
            sourceURL: sourceURL,
            status: .pending
        )
        items.insert(item, at: 0)

        let key = ObjectIdentifier(download)
        let observation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            self?.updateProgress(for: key, progress: progress.fractionCompleted)
        }
        wkContexts[key] = WKDownloadContext(
            itemID: item.id,
            download: download,
            progressObservation: observation,
            webViewBox: WeakWebViewBox(webView: webView)
        )
    }

    func chooseDestination(suggestedFilename: String, completion: @escaping (URL?) -> Void) {
        if !askWhereToSaveEachFile {
            completion(autoDestinationURL(suggestedFilename: suggestedFilename))
            return
        }

        let panel = NSSavePanel()
        panel.title = "Save Download"
        panel.nameFieldStringValue = safeFilename(from: suggestedFilename)
        panel.directoryURL = defaultDownloadFolder

        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }

    func didChooseDestination(for download: WKDownload, destination: URL?) {
        let key = ObjectIdentifier(download)
        guard let itemID = wkContexts[key]?.itemID else { return }

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
        guard let context = wkContexts[key] else { return }

        updateItem(id: context.itemID) { item in
            item.progress = 1
            item.status = .completed
            item.resumeData = nil
            item.errorDescription = nil
        }
        context.progressObservation.invalidate()
        wkContexts[key] = nil
        pendingFailureActions[key] = nil
    }

    func didFail(download: WKDownload, error: Error, resumeData: Data?) {
        let key = ObjectIdentifier(download)
        guard let context = wkContexts[key] else { return }

        let pendingAction = pendingFailureActions[key]
        updateItem(id: context.itemID) { item in
            switch pendingAction {
            case .pause:
                item.status = (resumeData != nil) ? .paused : .failed
                item.resumeData = resumeData
                item.errorDescription = (resumeData == nil) ? "Unable to pause this download." : nil
            case .cancel:
                item.status = .cancelled
                item.resumeData = nil
                item.errorDescription = nil
            case .none:
                item.status = .failed
                item.resumeData = resumeData
                item.errorDescription = error.localizedDescription
            }
        }
        context.progressObservation.invalidate()
        wkContexts[key] = nil
        pendingFailureActions[key] = nil
    }

    func pause(itemID: UUID) {
        if let key = wkContexts.first(where: { $0.value.itemID == itemID })?.key {
            pendingFailureActions[key] = .pause
            wkContexts[key]?.download.cancel({ _ in })
            return
        }

        if let taskID = retryTasksByTaskID.first(where: { $0.value.itemID == itemID })?.key,
           let task = retryDownloadTasksByTaskID[taskID] {
            task.cancel(byProducingResumeData: { [weak self] data in
                self?.updateItem(id: itemID) { item in
                    item.status = (data != nil) ? .paused : .failed
                    item.resumeData = data
                    item.errorDescription = (data == nil) ? "Unable to pause this download." : nil
                }
                self?.retryTasksByTaskID[taskID] = nil
                self?.retryDownloadTasksByTaskID[taskID] = nil
            })
        }
    }

    func resume(itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }),
              let resumeData = item.resumeData else {
            return
        }

        if let context = wkContexts.first(where: { $0.value.itemID == itemID })?.value,
           let webView = context.webViewBox.webView {
            webView.resumeDownload(fromResumeData: resumeData) { [weak self] _ in
                self?.updateItem(id: itemID) { item in
                    item.status = .failed
                    item.errorDescription = "Failed to resume this download."
                }
            }
            updateItem(id: itemID) { item in
                item.status = .downloading
                item.errorDescription = nil
                item.resumeData = nil
            }
            return
        }

        let task = retrySession.downloadTask(withResumeData: resumeData)
        guard let destination = item.destination ?? autoDestinationURL(suggestedFilename: item.filename) else {
            updateItem(id: itemID) { item in
                item.status = .failed
                item.errorDescription = "Unable to determine destination for resumed download."
            }
            return
        }
        retryTasksByTaskID[task.taskIdentifier] = RetryTaskContext(
            itemID: itemID,
            destination: destination,
            sourceURL: item.sourceURL ?? destination
        )
        retryDownloadTasksByTaskID[task.taskIdentifier] = task
        updateItem(id: itemID) { item in
            item.status = .downloading
            item.errorDescription = nil
            item.resumeData = nil
        }
        task.resume()
    }

    func cancel(itemID: UUID) {
        if let key = wkContexts.first(where: { $0.value.itemID == itemID })?.key {
            pendingFailureActions[key] = .cancel
            wkContexts[key]?.download.cancel({ _ in })
            return
        }

        if let taskID = retryTasksByTaskID.first(where: { $0.value.itemID == itemID })?.key,
           let task = retryDownloadTasksByTaskID[taskID] {
            task.cancel()
            retryTasksByTaskID[taskID] = nil
            retryDownloadTasksByTaskID[taskID] = nil
            updateItem(id: itemID) { item in
                item.status = .cancelled
                item.errorDescription = nil
                item.resumeData = nil
            }
        }
    }

    func retry(itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }),
              let sourceURL = item.sourceURL else {
            return
        }

        guard let destination = askWhereToSaveEachFile
            ? nil
            : autoDestinationURL(suggestedFilename: item.filename) else {
            updateItem(id: itemID) { item in
                item.status = .failed
                item.errorDescription = "Unable to determine destination for retry."
            }
            return
        }

        let startRetryWithDestination: (URL?) -> Void = { [weak self] selectedDestination in
            guard let self else { return }
            guard let selectedDestination else {
                self.updateItem(id: itemID) { item in
                    item.status = .cancelled
                }
                return
            }

            let task = self.retrySession.downloadTask(with: sourceURL)
            self.retryTasksByTaskID[task.taskIdentifier] = RetryTaskContext(
                itemID: itemID,
                destination: selectedDestination,
                sourceURL: sourceURL
            )
            self.retryDownloadTasksByTaskID[task.taskIdentifier] = task
            self.updateItem(id: itemID) { item in
                item.status = .downloading
                item.progress = 0
                item.errorDescription = nil
                item.resumeData = nil
                item.destination = selectedDestination
            }
            task.resume()
        }

        if askWhereToSaveEachFile {
            chooseDestination(suggestedFilename: item.filename, completion: startRetryWithDestination)
        } else {
            startRetryWithDestination(destination)
        }
    }

    func revealInFinder(itemID: UUID) {
        guard let destination = items.first(where: { $0.id == itemID })?.destination else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    func openFile(itemID: UUID) {
        guard let destination = items.first(where: { $0.id == itemID })?.destination else { return }
        guard fileManager.fileExists(atPath: destination.path) else { return }
        NSWorkspace.shared.open(destination)
    }

    func clearCompleted() {
        items.removeAll { $0.status == .completed }
    }

    func canPause(_ item: DownloadItem) -> Bool {
        guard item.status == .downloading || item.status == .pending else { return false }
        let hasWK = wkContexts.contains(where: { $0.value.itemID == item.id })
        let hasRetry = retryTasksByTaskID.contains(where: { $0.value.itemID == item.id })
        return hasWK || hasRetry
    }

    func canResume(_ item: DownloadItem) -> Bool {
        item.status == .paused && item.resumeData != nil
    }

    func canCancel(_ item: DownloadItem) -> Bool {
        canPause(item) || item.status == .paused
    }

    func canRetry(_ item: DownloadItem) -> Bool {
        guard item.sourceURL != nil else { return false }
        return item.status == .failed || item.status == .cancelled || item.status == .completed
    }

    func canReveal(_ item: DownloadItem) -> Bool {
        guard let destination = item.destination else { return false }
        return fileManager.fileExists(atPath: destination.path)
    }

    func canOpen(_ item: DownloadItem) -> Bool {
        guard item.status == .completed else { return false }
        guard let destination = item.destination else { return false }
        return fileManager.fileExists(atPath: destination.path)
    }

    private func setDefaultDownloadFolder(_ folderURL: URL) {
        defaultDownloadFolder = folderURL
        if let bookmark = try? folderURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            userDefaults.set(bookmark, forKey: defaultFolderBookmarkKey)
        }
    }

    private func autoDestinationURL(suggestedFilename: String) -> URL? {
        let filename = safeFilename(from: suggestedFilename)
        let folderURL = defaultDownloadFolder
        if !fileManager.fileExists(atPath: folderURL.path) {
            return nil
        }
        return uniqueDestinationURL(in: folderURL, filename: filename)
    }

    private func uniqueDestinationURL(in directory: URL, filename: String) -> URL {
        let baseURL = directory.appendingPathComponent(filename)
        if !fileManager.fileExists(atPath: baseURL.path) {
            return baseURL
        }

        let ext = baseURL.pathExtension
        let baseName = baseURL.deletingPathExtension().lastPathComponent
        let folder = baseURL.deletingLastPathComponent()
        var copyIndex = 1
        while true {
            let candidateName: String
            if ext.isEmpty {
                candidateName = "\(baseName) (\(copyIndex))"
            } else {
                candidateName = "\(baseName) (\(copyIndex)).\(ext)"
            }
            let candidate = folder.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            copyIndex += 1
        }
    }

    private func updateProgress(for key: ObjectIdentifier, progress: Double) {
        guard let itemID = wkContexts[key]?.itemID else { return }

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

extension DownloadManager: URLSessionDownloadDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let context = retryTasksByTaskID[downloadTask.taskIdentifier] else { return }
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        updateItem(id: context.itemID) { item in
            item.progress = max(0, min(1, progress))
            if item.status == .pending || item.status == .paused {
                item.status = .downloading
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let context = retryTasksByTaskID[downloadTask.taskIdentifier] else { return }
        let destination = uniqueDestinationURL(in: context.destination.deletingLastPathComponent(), filename: context.destination.lastPathComponent)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
            updateItem(id: context.itemID) { item in
                item.destination = destination
                item.progress = 1
                item.status = .completed
                item.errorDescription = nil
                item.resumeData = nil
            }
        } catch {
            updateItem(id: context.itemID) { item in
                item.status = .failed
                item.errorDescription = error.localizedDescription
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let context = retryTasksByTaskID[task.taskIdentifier] else { return }
        defer {
            retryTasksByTaskID[task.taskIdentifier] = nil
            retryDownloadTasksByTaskID[task.taskIdentifier] = nil
        }
        guard let error else { return }

        let nsError = error as NSError
        let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        updateItem(id: context.itemID) { item in
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                item.status = .cancelled
            } else {
                item.status = .failed
                item.errorDescription = nsError.localizedDescription
                item.resumeData = resumeData
            }
        }
    }
}
