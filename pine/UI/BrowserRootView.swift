import SwiftUI

struct BrowserRootView: View {
    @StateObject private var viewModel = BrowserViewModel()
    @State private var isHistoryPresented = false
    @State private var isBookmarksPresented = false
    @State private var isDownloadsPresented = false

    var body: some View {
        VStack(spacing: 0) {
            AddressBarView(viewModel: viewModel)
            loadingProgressBar
            Divider()
            tabStrip
            Divider()

            if let selectedTabID = viewModel.selectedTabID {
                WebViewContainer(viewModel: viewModel, tabID: selectedTabID)
                    .id(selectedTabID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Spacer()
                    Text("No tab selected")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("New Tab") {
                    viewModel.newTab(focusAddressBar: true)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    viewModel.closeCurrentTab()
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("History") {
                    isHistoryPresented = true
                }

                Button(viewModel.isCurrentPageBookmarked() ? "★" : "☆") {
                    viewModel.toggleBookmarkForSelectedTab()
                }

                Button("Bookmarks") {
                    isBookmarksPresented = true
                }

                Button("Downloads") {
                    isDownloadsPresented = true
                }
            }
        }
        .background {
            Button("Focus Address") {
                viewModel.requestAddressBarFocus(selectAll: true)
            }
            .keyboardShortcut("l", modifiers: .command)
            .hidden()
        }
        .sheet(isPresented: $isHistoryPresented) {
            HistorySheetView(
                historyStore: viewModel.historyStore,
                onSelect: { entry in
                    viewModel.loadHistoryEntryInSelectedTab(entry)
                    isHistoryPresented = false
                }
            )
        }
        .sheet(isPresented: $isBookmarksPresented) {
            BookmarksSheetView(
                bookmarksStore: viewModel.bookmarksStore,
                onSelect: { bookmark in
                    viewModel.loadBookmarkInSelectedTab(bookmark)
                    isBookmarksPresented = false
                }
            )
        }
        .sheet(isPresented: $isDownloadsPresented) {
            DownloadsSheetView(downloadManager: viewModel.downloadManager)
        }
    }

    @ViewBuilder
    private var loadingProgressBar: some View {
        if let tab = viewModel.selectedTab, tab.isLoading {
            ProgressView(value: tab.estimatedProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.tabs) { tab in
                    HStack(spacing: 6) {
                        if tab.isLoading {
                            Text("...")
                                .foregroundStyle(.secondary)
                        }

                        Text(tab.title)
                            .lineLimit(1)

                        Button {
                            viewModel.closeTab(id: tab.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tab.id == viewModel.selectedTabID ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        viewModel.selectTab(id: tab.id)
                    }
                }

                Button {
                    viewModel.newTab(focusAddressBar: true)
                } label: {
                    Image(systemName: "plus")
                        .padding(6)
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
        }
    }
}

private struct HistorySheetView: View {
    @ObservedObject var historyStore: HistoryStore
    let onSelect: (HistoryEntry) -> Void

    var body: some View {
        NavigationStack {
            List(historyStore.entries) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .lineLimit(1)
                        Text(entry.urlString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("History")
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}

private struct BookmarksSheetView: View {
    @ObservedObject var bookmarksStore: BookmarksStore
    let onSelect: (Bookmark) -> Void

    var body: some View {
        NavigationStack {
            List(bookmarksStore.bookmarks) { bookmark in
                Button {
                    onSelect(bookmark)
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
            .navigationTitle("Bookmarks")
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}

private struct DownloadsSheetView: View {
    @ObservedObject var downloadManager: DownloadManager

    var body: some View {
        NavigationStack {
            List(downloadManager.items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.filename)
                        .lineLimit(1)
                    if let destination = item.destination {
                        Text(destination.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        ProgressView(value: item.progress)
                            .frame(maxWidth: .infinity)
                        Text(item.status.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("Downloads")
        }
        .frame(minWidth: 560, minHeight: 360)
    }
}

#Preview {
    BrowserRootView()
}
