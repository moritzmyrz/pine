import Foundation

struct WorkspacePersistedState: Codable {
    var workspaces: [Workspace]
    var currentWorkspaceID: UUID?
}

final class WorkspaceStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let workspacesFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directoryURL = appSupport.appendingPathComponent("pine", isDirectory: true)
        workspacesFileURL = directoryURL.appendingPathComponent("workspaces.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func loadState() -> WorkspacePersistedState {
        guard let data = try? Data(contentsOf: workspacesFileURL),
              let decoded = try? decoder.decode(WorkspacePersistedState.self, from: data) else {
            return WorkspacePersistedState(workspaces: [], currentWorkspaceID: nil)
        }
        return decoded
    }

    func saveState(workspaces: [Workspace], currentWorkspaceID: UUID?) {
        do {
            try createDirectoryIfNeeded()
            let state = WorkspacePersistedState(workspaces: workspaces, currentWorkspaceID: currentWorkspaceID)
            let data = try encoder.encode(state)
            try data.write(to: workspacesFileURL, options: .atomic)
        } catch {
            return
        }
    }

    private func createDirectoryIfNeeded() throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
}
