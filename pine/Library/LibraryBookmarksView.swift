import SwiftUI

struct LibraryBookmarksView: View {
    @ObservedObject private var bookmarksStore = SharedStores.shared.bookmarksStore
    @State private var searchText = ""

    var body: some View {
        BookmarksTreeView(
            bookmarksStore: bookmarksStore,
            searchText: searchText,
            onOpenBookmark: { bookmark in
                BrowserWindowManager.shared.openURLInFrontmostWindow(bookmark.urlString)
            }
        )
        .searchable(text: $searchText, prompt: "Search bookmarks")
        .navigationTitle("Bookmarks")
    }
}
