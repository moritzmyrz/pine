import SwiftUI

struct LibraryBookmarksView: View {
    @ObservedObject private var bookmarksStore = SharedStores.shared.bookmarksStore
    @State private var searchText = ""
    @State private var isNewFolderAlertPresented = false
    @State private var newFolderName = ""

    var body: some View {
        List {
            ForEach(groupedBookmarks) { group in
                Section(group.title) {
                    ForEach(group.entries) { bookmark in
                        Button {
                            BrowserWindowManager.shared.openURLInFrontmostWindow(bookmark.urlString)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    Text(bookmark.title)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(bookmark.folderName ?? "Unsorted")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(bookmark.urlString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Menu("Move to Folder") {
                                Button("Unsorted") {
                                    bookmarksStore.setFolderName(nil, for: bookmark.id)
                                }
                                Divider()
                                ForEach(bookmarksStore.folderNames, id: \.self) { folderName in
                                    Button(folderName) {
                                        bookmarksStore.setFolderName(folderName, for: bookmark.id)
                                    }
                                }
                            }
                            Button("Delete Bookmark", role: .destructive) {
                                bookmarksStore.removeBookmark(id: bookmark.id)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if groupedBookmarks.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Bookmarks Yet" : "No Matching Bookmarks",
                    systemImage: "bookmark",
                    description: Text(
                        searchText.isEmpty
                        ? "Use the star button in the toolbar to save pages."
                        : "Try a different search term."
                    )
                )
            }
        }
        .searchable(text: $searchText, prompt: "Search bookmarks")
        .navigationTitle("Bookmarks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Folder") {
                    newFolderName = ""
                    isNewFolderAlertPresented = true
                }
            }
        }
        .alert("New Bookmark Folder", isPresented: $isNewFolderAlertPresented) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                createFolder()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Folders can be assigned from each bookmark's context menu.")
        }
    }

    private var filteredBookmarks: [Bookmark] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return bookmarksStore.bookmarks }

        return bookmarksStore.bookmarks.filter { bookmark in
            bookmark.title.lowercased().contains(query)
                || bookmark.urlString.lowercased().contains(query)
                || (bookmark.folderName?.lowercased().contains(query) == true)
        }
    }

    private var groupedBookmarks: [BookmarkGroup] {
        let grouped = Dictionary(grouping: filteredBookmarks) { bookmark in
            bookmark.folderName ?? ""
        }

        let folderKeys = grouped.keys.filter { !$0.isEmpty }.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        var groups: [BookmarkGroup] = folderKeys.map { folder in
            BookmarkGroup(title: folder, entries: grouped[folder, default: []])
        }

        let unsorted = grouped["", default: []]
        if !unsorted.isEmpty {
            groups.insert(BookmarkGroup(title: "Unsorted", entries: unsorted), at: 0)
        }
        return groups
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        bookmarksStore.addFolder(named: trimmed)
    }
}

private struct BookmarkGroup: Identifiable {
    let title: String
    let entries: [Bookmark]

    var id: String { title }
}
