import SwiftUI

struct BookmarksBarView: View {
    @ObservedObject var viewModel: BrowserViewModel

    private var topLevelBookmarks: [Bookmark] {
        viewModel.bookmarksStore.bookmarks.filter { $0.folderName == nil }
    }

    private var folderNames: [String] {
        viewModel.bookmarksStore.folderNames
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(folderNames, id: \.self) { folder in
                    Menu(folder) {
                        ForEach(bookmarks(in: folder)) { bookmark in
                            Button(bookmark.title) {
                                viewModel.loadBookmarkInSelectedTab(bookmark)
                            }
                        }
                    }
                }

                ForEach(topLevelBookmarks) { bookmark in
                    Button(bookmark.title) {
                        viewModel.loadBookmarkInSelectedTab(bookmark)
                    }
                    .buttonStyle(.borderless)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func bookmarks(in folder: String) -> [Bookmark] {
        viewModel.bookmarksStore.bookmarks.filter { $0.folderName == folder }
    }
}
