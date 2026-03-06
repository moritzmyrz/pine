import Foundation

struct WorkspaceTabSnapshot: Codable, Hashable {
    var profileID: UUID
    var urlString: String
    var title: String
}

struct Workspace: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var tabSnapshots: [WorkspaceTabSnapshot]
    var pinnedSnapshots: [WorkspaceTabSnapshot]

    init(
        id: UUID = UUID(),
        name: String,
        tabSnapshots: [WorkspaceTabSnapshot],
        pinnedSnapshots: [WorkspaceTabSnapshot]
    ) {
        self.id = id
        self.name = name
        self.tabSnapshots = tabSnapshots
        self.pinnedSnapshots = pinnedSnapshots
    }
}
