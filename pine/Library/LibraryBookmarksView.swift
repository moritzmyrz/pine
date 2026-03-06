import SwiftUI

struct LibraryBookmarksView: View {
    @ObservedObject private var bookmarksStore = SharedStores.shared.bookmarksStore
    @State private var searchText = ""

    var body: some View {
        List(filteredBookmarks) { bookmark in
            Button {
                BrowserWindowManager.shared.openURLInFrontmostWindow(bookmark.urlString)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bookmark.title)
                        .lineLimit(1)
                    Text(bookmark.urlString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if filteredBookmarks.isEmpty {
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
    }

    private var filteredBookmarks: [Bookmark] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return bookmarksStore.bookmarks }

        return bookmarksStore.bookmarks.filter { bookmark in
            bookmark.title.lowercased().contains(query) || bookmark.urlString.lowercased().contains(query)
        }
    }
}
