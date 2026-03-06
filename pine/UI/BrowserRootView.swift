import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BrowserRootView: View {
    @StateObject private var viewModel = BrowserViewModel()
    @State private var isHistoryPresented = false
    @State private var isBookmarksPresented = false
    @State private var isDownloadsPresented = false
    @State private var isTabSearchPresented = false
    @State private var tabSearchQuery = ""
    @State private var draggedTabID: UUID?
    @FocusState private var isTabSearchFieldFocused: Bool

    var body: some View {
        configuredRootView
    }

    private var configuredRootView: some View {
        rootLayout
            .animation(.easeInOut(duration: 0.15), value: isTabSearchPresented)
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
            .onReceive(NotificationCenter.default.publisher(for: .pineShowHistory)) { _ in
                isHistoryPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .pineShowBookmarks)) { _ in
                isBookmarksPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .pineShowTabSearch)) { _ in
                tabSearchQuery = ""
                isTabSearchPresented = true
                isTabSearchFieldFocused = true
            }
    }

    private var rootLayout: some View {
        ZStack {
            VStack(spacing: 0) {
                AddressBarView(viewModel: viewModel)
                loadingProgressBar
                Divider()
                tabStrip
                Divider()

                if let selectedTab = viewModel.selectedTab {
                    if selectedTab.urlString == "about:blank" {
                        blankTabState
                    } else {
                        WebViewContainer(viewModel: viewModel, tabID: selectedTab.id)
                            .id(selectedTab.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
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

                    Button("New Private Tab") {
                        viewModel.newPrivateTab(focusAddressBar: true)
                    }

                    Button("Close Tab") {
                        viewModel.closeCurrentTab()
                    }

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

                    readingToolbarMenu
                    sessionToolbarMenu
                }
            }
            .background {
                Button("Focus Address") {
                    viewModel.requestAddressBarFocus(selectAll: true)
                }
                .keyboardShortcut("l", modifiers: .command)
                .hidden()
            }

            if isTabSearchPresented {
                tabSearchOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
            }
        }
    }

    @ViewBuilder
    private var loadingProgressBar: some View {
        if let tab = viewModel.selectedTab, tab.isLoading {
            ProgressView(value: tab.estimatedProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    private var blankTabState: some View {
        VStack(spacing: 8) {
            Text("New Tab")
                .font(.title2)
            Text("Type a URL or search term in the address bar to start browsing.")
                .foregroundStyle(.secondary)
            Text("Tip: Press Cmd+L to focus the address bar.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.sortedTabs) { tab in
                    HStack(spacing: 6) {
                        if tab.isPinned {
                            if let favicon = faviconImage(for: tab) {
                                Image(nsImage: favicon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 16, height: 16)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Text(pinnedTabSymbol(for: tab))
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 18, height: 18)
                                    .background(Color.secondary.opacity(0.14))
                                    .clipShape(Circle())
                            }
                        } else {
                            if let favicon = faviconImage(for: tab) {
                                Image(nsImage: favicon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 14, height: 14)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            if tab.isLoading {
                                Text("...")
                                    .foregroundStyle(.secondary)
                            }

                            if tab.isPrivate {
                                Text("Private")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.2))
                                    .clipShape(Capsule())
                            }

                            Text(tab.title)
                                .lineLimit(1)
                        }
                        if !tab.isPinned {
                            Button {
                                viewModel.closeTab(id: tab.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, tab.isPinned ? 8 : 10)
                    .padding(.vertical, 6)
                    .background(tab.id == viewModel.selectedTabID ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        MiddleClickCatcher {
                            viewModel.closeTab(id: tab.id)
                        }
                    }
                    .onTapGesture {
                        viewModel.selectTab(id: tab.id)
                    }
                    .contextMenu {
                        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
                            viewModel.setTabPinned(id: tab.id, isPinned: !tab.isPinned)
                        }
                        Button("Duplicate Tab") {
                            viewModel.duplicateTab(id: tab.id)
                        }
                        Divider()
                        Button("Close Other Tabs") {
                            viewModel.closeOtherTabs(keeping: tab.id)
                        }
                        .disabled(viewModel.tabs.count <= 1)
                        Button("Close Tabs to the Right") {
                            viewModel.closeTabsToRight(of: tab.id)
                        }
                        .disabled(isRightMostTab(tab.id))
                    }
                    .onDrag {
                        draggedTabID = tab.id
                        return NSItemProvider(object: tab.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: TabDropDelegate(
                            targetTabID: tab.id,
                            draggedTabID: $draggedTabID,
                            onMove: { draggedID, targetID in
                                viewModel.reorderTab(draggedID: draggedID, before: targetID)
                            }
                        )
                    )
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

    private var tabSearchOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    isTabSearchPresented = false
                }

            VStack(spacing: 10) {
                TextField("Search tabs by title or URL", text: $tabSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTabSearchFieldFocused)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if filteredTabsForSearch.isEmpty {
                            Text("No matching tabs")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(filteredTabsForSearch) { tab in
                                Button {
                                    viewModel.selectTab(id: tab.id)
                                    isTabSearchPresented = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(tab.title)
                                            .lineLimit(1)
                                        Text(tab.urlString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .padding(14)
            .frame(width: 560)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
        .onAppear {
            isTabSearchFieldFocused = true
        }
        .onExitCommand {
            isTabSearchPresented = false
        }
    }

    private var filteredTabsForSearch: [Tab] {
        viewModel.tabsMatching(query: tabSearchQuery)
    }

    private func isRightMostTab(_ id: UUID) -> Bool {
        viewModel.sortedTabs.last?.id == id
    }

    private func pinnedTabSymbol(for tab: Tab) -> String {
        let trimmedTitle = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstCharacter = trimmedTitle.first {
            return String(firstCharacter).uppercased()
        }

        if let host = URL(string: tab.urlString)?.host, let firstHostCharacter = host.first {
            return String(firstHostCharacter).uppercased()
        }

        return "•"
    }

    private func faviconImage(for tab: Tab) -> NSImage? {
        guard let faviconData = tab.faviconData else { return nil }
        return NSImage(data: faviconData)
    }

    private var readerModeButtonTitle: String {
        (viewModel.selectedTab?.isReaderModeEnabled == true) ? "Disable Reader Mode (Lite)" : "Enable Reader Mode (Lite)"
    }

    private var readingToolbarMenu: some View {
        Menu("Reading") {
            Button("Zoom In") {
                viewModel.zoomInSelectedTab()
            }
            Button("Zoom Out") {
                viewModel.zoomOutSelectedTab()
            }
            Button("Actual Size") {
                viewModel.resetZoomSelectedTab()
            }
            Divider()
            Button(readerModeButtonTitle) {
                viewModel.toggleReaderModeForSelectedTab()
            }
        }
    }

    private var sessionToolbarMenu: some View {
        Menu("Session") {
            Button("Reopen Closed Tab") {
                viewModel.reopenClosedTab()
            }

            Divider()

            Button(restoreSessionMenuTitle) {
                viewModel.setRestorePreviousSessionEnabled(!viewModel.sessionSettings.restorePreviousSession)
            }

            Button(includePrivateTabsMenuTitle) {
                viewModel.setIncludePrivateTabsInSession(!viewModel.sessionSettings.includePrivateTabsInSession)
            }
        }
    }

    private var restoreSessionMenuTitle: String {
        viewModel.sessionSettings.restorePreviousSession
            ? "Disable Restore Previous Session"
            : "Enable Restore Previous Session"
    }

    private var includePrivateTabsMenuTitle: String {
        viewModel.sessionSettings.includePrivateTabsInSession
            ? "Disable Private Tabs in Session"
            : "Enable Private Tabs in Session"
    }
}

private struct TabDropDelegate: DropDelegate {
    let targetTabID: UUID
    @Binding var draggedTabID: UUID?
    let onMove: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedTabID else { return }
        guard draggedTabID != targetTabID else { return }
        onMove(draggedTabID, targetTabID)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        return true
    }
}

private struct MiddleClickCatcher: NSViewRepresentable {
    let onMiddleClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMiddleClick: onMiddleClick)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        let recognizer = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMiddleClick))
        recognizer.buttonMask = 0x4
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator: NSObject {
        let onMiddleClick: () -> Void

        init(onMiddleClick: @escaping () -> Void) {
            self.onMiddleClick = onMiddleClick
        }

        @objc
        func handleMiddleClick() {
            onMiddleClick()
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
            .overlay {
                if historyStore.entries.isEmpty {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Visited pages will appear here.")
                    )
                }
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
            .overlay {
                if bookmarksStore.bookmarks.isEmpty {
                    ContentUnavailableView(
                        "No Bookmarks Yet",
                        systemImage: "bookmark",
                        description: Text("Use the star button in the toolbar to save pages.")
                    )
                }
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
