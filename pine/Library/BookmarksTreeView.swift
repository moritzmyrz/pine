import SwiftUI

struct BookmarksTreeView: View {
    @ObservedObject var bookmarksStore: BookmarksStore
    let searchText: String
    let onOpenBookmark: (Bookmark) -> Void

    @State private var expandedFolders: Set<UUID> = []
    @State private var newFolderParentID: UUID?
    @State private var newFolderName = ""
    @State private var isNewFolderAlertPresented = false
    @State private var renameFolderID: UUID?
    @State private var renameFolderName = ""
    @State private var isRenameFolderAlertPresented = false
    @State private var renameBookmarkID: UUID?
    @State private var renameBookmarkTitle = ""
    @State private var isRenameBookmarkAlertPresented = false

    var body: some View {
        List {
            if isSearching {
                searchResultsContent
            } else {
                treeContent
            }
        }
        .dropDestination(for: String.self) { items, _ in
            return handleDrop(items: items, toFolderID: nil)
        }
        .overlay {
            if bookmarksStore.bookmarks.isEmpty && bookmarksStore.folders.isEmpty {
                ContentUnavailableView(
                    "No Bookmarks Yet",
                    systemImage: "bookmark",
                    description: Text("Use Cmd+B to bookmark the current page.")
                )
            } else if isSearching && filteredBookmarks.isEmpty {
                ContentUnavailableView(
                    "No Matching Bookmarks",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Folder") {
                    newFolderParentID = nil
                    newFolderName = ""
                    isNewFolderAlertPresented = true
                }
            }
        }
        .alert("New Folder", isPresented: $isNewFolderAlertPresented) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                let createdID = bookmarksStore.addFolder(named: newFolderName, parentID: newFolderParentID)
                if let createdID {
                    expandedFolders.insert(createdID)
                    if let parentID = newFolderParentID {
                        expandedFolders.insert(parentID)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Folder", isPresented: $isRenameFolderAlertPresented) {
            TextField("Folder name", text: $renameFolderName)
            Button("Save") {
                guard let renameFolderID else { return }
                bookmarksStore.renameFolder(id: renameFolderID, to: renameFolderName)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Bookmark", isPresented: $isRenameBookmarkAlertPresented) {
            TextField("Title", text: $renameBookmarkTitle)
            Button("Save") {
                guard let renameBookmarkID else { return }
                bookmarksStore.renameBookmark(id: renameBookmarkID, to: renameBookmarkTitle)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var treeContent: some View {
        ForEach(bookmarksStore.rootFolders()) { folder in
            folderNode(folder)
        }
        ForEach(bookmarksStore.bookmarks(in: nil)) { bookmark in
            bookmarkRow(bookmark)
        }
    }

    private var searchResultsContent: some View {
        ForEach(filteredBookmarks) { bookmark in
            bookmarkRow(bookmark)
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredBookmarks: [Bookmark] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return bookmarksStore.bookmarks }
        return bookmarksStore.bookmarks.filter { bookmark in
            bookmark.title.lowercased().contains(query)
                || bookmark.urlString.lowercased().contains(query)
                || bookmarksStore.folderPath(for: bookmark.folderID).lowercased().contains(query)
        }
    }

    private func folderNode(_ folder: BookmarkFolder) -> AnyView {
        AnyView(
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedFolders.contains(folder.id) },
                    set: { isExpanded in
                        if isExpanded { expandedFolders.insert(folder.id) } else { expandedFolders.remove(folder.id) }
                    }
                )
            ) {
                ForEach(bookmarksStore.childFolders(of: folder.id)) { child in
                    folderNode(child)
                }
                ForEach(bookmarksStore.bookmarks(in: folder.id)) { bookmark in
                    bookmarkRow(bookmark)
                }
            } label: {
                Label(folder.name, systemImage: "folder")
                    .lineLimit(1)
            }
            .contextMenu {
                Button("New Subfolder") {
                    newFolderParentID = folder.id
                    newFolderName = ""
                    isNewFolderAlertPresented = true
                }
                Button("Rename Folder") {
                    renameFolderID = folder.id
                    renameFolderName = folder.name
                    isRenameFolderAlertPresented = true
                }
                Button("Delete Folder", role: .destructive) {
                    bookmarksStore.deleteFolder(id: folder.id)
                }
            }
            .draggable("folder:\(folder.id.uuidString)")
            .dropDestination(for: String.self) { items, _ in
                return handleDrop(items: items, toFolderID: folder.id)
            }
        )
    }

    private func bookmarkRow(_ bookmark: Bookmark) -> AnyView {
        AnyView(
            Button {
                onOpenBookmark(bookmark)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(bookmark.title)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(bookmark.urlString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(bookmarksStore.folderPath(for: bookmark.folderID))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Open") {
                    onOpenBookmark(bookmark)
                }
                Button("Rename") {
                    renameBookmarkID = bookmark.id
                    renameBookmarkTitle = bookmark.title
                    isRenameBookmarkAlertPresented = true
                }
                Menu("Move to Folder") {
                    Button("Unsorted") {
                        bookmarksStore.moveBookmark(id: bookmark.id, toFolderID: nil)
                    }
                    Divider()
                    ForEach(bookmarksStore.folders) { folder in
                        Button(bookmarksStore.folderPath(for: folder.id)) {
                            bookmarksStore.moveBookmark(id: bookmark.id, toFolderID: folder.id)
                        }
                    }
                }
                Button("Delete Bookmark", role: .destructive) {
                    bookmarksStore.removeBookmark(id: bookmark.id)
                }
            }
            .draggable("bookmark:\(bookmark.id.uuidString)")
        )
    }

    private func handleDrop(items: [String], toFolderID: UUID?) -> Bool {
        var moved = false
        for item in items {
            if let bookmarkID = parseID(item, prefix: "bookmark:") {
                bookmarksStore.moveBookmark(id: bookmarkID, toFolderID: toFolderID)
                moved = true
                continue
            }
            if let folderID = parseID(item, prefix: "folder:") {
                bookmarksStore.moveFolder(id: folderID, toParentID: toFolderID)
                if let toFolderID {
                    expandedFolders.insert(toFolderID)
                }
                moved = true
            }
        }
        return moved
    }

    private func parseID(_ value: String, prefix: String) -> UUID? {
        guard value.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(value.dropFirst(prefix.count)))
    }
}
