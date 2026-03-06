import SwiftUI

struct BookmarksBarView: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(viewModel.bookmarksStore.rootFolders()) { folder in
                    folderMenu(folder)
                }

                ForEach(viewModel.bookmarksStore.bookmarks(in: nil)) { bookmark in
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

    private func folderMenu(_ folder: BookmarkFolder) -> AnyView {
        AnyView(
            Menu(folder.name) {
                ForEach(viewModel.bookmarksStore.childFolders(of: folder.id)) { subfolder in
                    folderMenu(subfolder)
                }
                ForEach(viewModel.bookmarksStore.bookmarks(in: folder.id)) { bookmark in
                    Button(bookmark.title) {
                        viewModel.loadBookmarkInSelectedTab(bookmark)
                    }
                }
            }
        )
    }
}
