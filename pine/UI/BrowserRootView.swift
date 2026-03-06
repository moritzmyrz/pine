import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BrowserRootView: View {
    @StateObject private var viewModel = BrowserViewModel()
    @State private var draggedTabID: UUID?
    @State private var addressInput = ""
    @State private var isSiteSettingsPresented = false
    @State private var isTabsOverviewPresented = false
    @FocusState private var isAddressFieldFocused: Bool

    var body: some View {
        configuredRootView
    }

    private var configuredRootView: some View {
        rootLayout
            .sheet(isPresented: historySheetBinding) {
                HistorySheetView(
                    historyStore: viewModel.historyStore,
                    onSelect: { entry in
                        viewModel.loadHistoryEntryInSelectedTab(entry)
                        viewModel.store.isHistoryPresented = false
                    }
                )
            }
            .sheet(isPresented: bookmarksSheetBinding) {
                BookmarksSheetView(
                    bookmarksStore: viewModel.bookmarksStore,
                    onSelect: { bookmark in
                        viewModel.loadBookmarkInSelectedTab(bookmark)
                        viewModel.store.isBookmarksPresented = false
                    }
                )
            }
            .sheet(isPresented: downloadsSheetBinding) {
                DownloadsSheetView(downloadManager: viewModel.downloadManager)
            }
            .sheet(isPresented: settingsSheetBinding) {
                SettingsSheetView(viewModel: viewModel)
            }
            .sheet(isPresented: profileManagementSheetBinding) {
                ProfileManagementSheet(
                    viewModel: viewModel,
                    profilePendingDeletion: profilePendingDeletionBinding
                )
            }
            .sheet(isPresented: tabsOverviewSheetBinding) {
                TabsOverviewSheetView(viewModel: viewModel)
            }
            .alert("Delete Profile?", isPresented: profileDeleteConfirmationBinding, presenting: viewModel.store.profilePendingDeletion) { profile in
                Button("Delete", role: .destructive) {
                    viewModel.deleteProfile(id: profile.id)
                    viewModel.store.profilePendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    viewModel.store.profilePendingDeletion = nil
                }
            } message: { profile in
                Text("This removes the profile and its stored website data. Tabs in \(profile.name) will be closed.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .pineShowHistory)) { _ in
                viewModel.store.isHistoryPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .pineShowBookmarks)) { _ in
                viewModel.store.isBookmarksPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .pineShowTabSearch)) { _ in
                isTabsOverviewPresented = true
            }
    }

    private var rootLayout: some View {
        ZStack {
            VStack(spacing: 0) {
                BrowserTopBar(
                    viewModel: viewModel,
                    addressInput: addressInputBinding,
                    addressFieldFocus: $isAddressFieldFocused,
                    isSiteSettingsPresented: siteSettingsPresentedBinding,
                    isTabsOverviewPresented: tabsOverviewSheetBinding,
                    submitAddressBar: submitAddressBar
                )
                loadingProgressBar

                if viewModel.sessionSettings.showCompactTabStrip {
                    Divider()
                    tabStrip
                }

                browserContentArea

                if viewModel.downloadController.shouldShowShelf {
                    Divider()
                    DownloadsShelfView(
                        downloadManager: viewModel.downloadManager,
                        openDownloadsSheet: { viewModel.downloadController.showDownloadsSheet() },
                        closeShelf: { viewModel.downloadController.dismissShelf() }
                    )
                }
            }
            .background {
                Button("Focus Address") {
                    viewModel.requestAddressBarFocus(selectAll: true)
                }
                .keyboardShortcut("l", modifiers: .command)
                .hidden()
            }
        }
        .onAppear {
            addressInput = currentTabURL
        }
        .onChange(of: viewModel.selectedTabID) {
            addressInput = currentTabURL
        }
        .onChange(of: currentTabURL) {
            guard !isAddressFieldFocused else { return }
            addressInput = currentTabURL
        }
        .onChange(of: isAddressFieldFocused) {
            if !isAddressFieldFocused {
                addressInput = currentTabURL
            }
        }
        .onChange(of: viewModel.addressBarFocusToken) {
            isAddressFieldFocused = true
            guard viewModel.shouldSelectAllInAddressBar else { return }
            DispatchQueue.main.async {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                viewModel.consumeAddressBarSelectAllRequest()
            }
        }
    }

    @ViewBuilder
    private var browserContentArea: some View {
        if viewModel.isSplitViewEnabled,
           let primaryTabID = viewModel.splitPrimaryTabID,
           let secondaryTabID = viewModel.splitSecondaryTabID,
           primaryTabID != secondaryTabID,
           viewModel.tabs.contains(where: { $0.id == primaryTabID }),
           viewModel.tabs.contains(where: { $0.id == secondaryTabID }) {
            GeometryReader { geometry in
                let dividerWidth: CGFloat = 8
                let availableWidth = max(geometry.size.width - dividerWidth, 1)
                let primaryWidth = availableWidth * viewModel.splitRatio
                let secondaryWidth = availableWidth - primaryWidth

                HStack(spacing: 0) {
                    paneContainer(tabID: primaryTabID, pane: .primary)
                        .frame(width: primaryWidth)
                        .frame(maxHeight: .infinity)

                    SplitResizeDivider {
                        // Keep drag logic in one place and clamp in store.
                        let draggedRatio = $0 / availableWidth
                        viewModel.setSplitRatio(draggedRatio)
                    }
                    .frame(width: dividerWidth)
                    .frame(maxHeight: .infinity)

                    ZStack(alignment: .topLeading) {
                        paneContainer(tabID: secondaryTabID, pane: .secondary)
                            .frame(width: secondaryWidth)
                            .frame(maxHeight: .infinity)
                        SplitViewControls(
                            viewModel: viewModel,
                            primaryTabID: primaryTabID,
                            secondaryTabID: secondaryTabID
                        )
                        .padding(8)
                    }
                    .frame(width: secondaryWidth)
                    .frame(maxHeight: .infinity)
                }
                .coordinateSpace(name: "splitContainer")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let selectedTab = viewModel.selectedTab {
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

    @ViewBuilder
    private func tabContent(tabID: UUID) -> some View {
        if let tab = viewModel.tabs.first(where: { $0.id == tabID }), tab.urlString == "about:blank" {
            blankTabState
        } else {
            WebViewContainer(
                viewModel: viewModel,
                tabID: tabID,
                onActivate: {
                    if viewModel.isSplitViewEnabled,
                       let primaryTabID = viewModel.splitPrimaryTabID,
                       tabID != primaryTabID {
                        viewModel.setActivePane(.secondary)
                    } else {
                        viewModel.setActivePane(.primary)
                    }
                }
            )
                .id(tabID)
        }
    }

    private func paneContainer(tabID: UUID, pane: ActivePane) -> some View {
        tabContent(tabID: tabID)
            .overlay {
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        pane == viewModel.activePane ? Color.accentColor.opacity(0.22) : Color.clear,
                        lineWidth: 1
                    )
            }
            .onTapGesture {
                viewModel.setActivePane(pane)
            }
    }

    @ViewBuilder
    private var loadingProgressBar: some View {
        if let tab = viewModel.activeTab, tab.isLoading {
            ProgressView(value: tab.estimatedProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
    }

    private var blankTabState: some View {
        let profileLabel = viewModel.activeTab.map { viewModel.profileName(for: $0.profileID) } ?? "Unknown"
        return VStack(spacing: 8) {
            Text("New Tab")
                .font(.title2)
            Text("Profile: \(profileLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            HStack(spacing: 6) {
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

                            if viewModel.profiles.count > 1 {
                                Text(viewModel.profileName(for: tab.profileID))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.16))
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
                    .padding(.vertical, 5)
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
                        .padding(5)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color.gray.opacity(0.06))
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

    private var profileDeleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.store.profilePendingDeletion != nil },
            set: { shouldPresent in
                if !shouldPresent {
                    viewModel.store.profilePendingDeletion = nil
                }
            }
        )
    }

    private var historySheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.store.isHistoryPresented },
            set: { viewModel.store.isHistoryPresented = $0 }
        )
    }

    private var bookmarksSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.store.isBookmarksPresented },
            set: { viewModel.store.isBookmarksPresented = $0 }
        )
    }

    private var downloadsSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.store.isDownloadsPresented },
            set: { viewModel.store.isDownloadsPresented = $0 }
        )
    }

    private var settingsSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.store.isSettingsPresented },
            set: { viewModel.store.isSettingsPresented = $0 }
        )
    }

    private var profileManagementSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.store.isProfileManagementPresented },
            set: { viewModel.store.isProfileManagementPresented = $0 }
        )
    }

    private var profilePendingDeletionBinding: Binding<Profile?> {
        Binding(
            get: { viewModel.store.profilePendingDeletion },
            set: { viewModel.store.profilePendingDeletion = $0 }
        )
    }

    private var tabsOverviewSheetBinding: Binding<Bool> {
        Binding(
            get: { isTabsOverviewPresented },
            set: { isTabsOverviewPresented = $0 }
        )
    }

    private var addressInputBinding: Binding<String> {
        Binding(
            get: { addressInput },
            set: { addressInput = $0 }
        )
    }

    private var siteSettingsPresentedBinding: Binding<Bool> {
        Binding(
            get: { isSiteSettingsPresented },
            set: { isSiteSettingsPresented = $0 }
        )
    }

    private var currentTabURL: String {
        viewModel.activeTab?.urlString ?? ""
    }

    private func submitAddressBar() {
        viewModel.loadSelectedTab(from: addressInput)
    }
}

private struct SplitResizeDivider: View {
    let onDragToX: (CGFloat) -> Void

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(width: 1)
        }
        .contentShape(Rectangle())
        .gesture(onDragGesture)
    }

    private var onDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("splitContainer"))
            .onChanged { value in
                onDragToX(value.location.x)
            }
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
                DownloadRowView(downloadManager: downloadManager, item: item, compact: false)
            }
            .navigationTitle("Downloads")
        }
        .frame(minWidth: 560, minHeight: 360)
    }
}

private struct DownloadsShelfView: View {
    @ObservedObject var downloadManager: DownloadManager
    let openDownloadsSheet: () -> Void
    let closeShelf: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("Downloads")
                .font(.subheadline.weight(.semibold))

            ForEach(downloadManager.shelfItems) { item in
                DownloadRowView(downloadManager: downloadManager, item: item, compact: true)
                    .frame(maxWidth: 280)
            }

            Spacer(minLength: 0)

            Button("Show All") {
                openDownloadsSheet()
            }
            .buttonStyle(.bordered)

            Button {
                closeShelf()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
            }
            .buttonStyle(.plain)
            .help("Hide downloads shelf")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }
}

private struct DownloadRowView: View {
    @ObservedObject var downloadManager: DownloadManager
    let item: DownloadItem
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(spacing: 6) {
                Text(item.filename)
                    .font(compact ? .caption : .body)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(item.status.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: item.progress)
                .frame(maxWidth: .infinity)

            if !compact, let destination = item.destination {
                Text(destination.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let errorDescription = item.errorDescription, !errorDescription.isEmpty {
                Text(errorDescription)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if downloadManager.canPause(item) {
                    Button("Pause") {
                        downloadManager.pause(itemID: item.id)
                    }
                } else if downloadManager.canResume(item) {
                    Button("Resume") {
                        downloadManager.resume(itemID: item.id)
                    }
                }

                if downloadManager.canCancel(item) {
                    Button("Cancel") {
                        downloadManager.cancel(itemID: item.id)
                    }
                }

                Button("Reveal") {
                    downloadManager.revealInFinder(itemID: item.id)
                }
                .disabled(!downloadManager.canReveal(item))

                Button("Retry") {
                    downloadManager.retry(itemID: item.id)
                }
                .disabled(!downloadManager.canRetry(item))
            }
            .font(.caption)
        }
        .padding(compact ? 8 : 4)
        .background(compact ? Color.gray.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProfileManagementSheet: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Binding var profilePendingDeletion: Profile?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                List {
                    ForEach(viewModel.profiles) { profile in
                        HStack(spacing: 10) {
                            TextField(
                                "Profile Name",
                                text: Binding(
                                    get: { viewModel.profileName(for: profile.id) },
                                    set: { viewModel.renameProfile(id: profile.id, to: $0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)

                            if profile.isDefault {
                                Text("Default")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.18))
                                    .clipShape(Capsule())
                            }

                            Spacer()

                            Button(role: .destructive) {
                                profilePendingDeletion = profile
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(!viewModel.canDeleteProfile(id: profile.id))
                        }
                        .padding(.vertical, 2)
                    }
                }

                HStack {
                    Button("New Profile") {
                        let newProfileID = viewModel.createProfile(named: nil)
                        viewModel.selectProfile(id: newProfileID)
                    }
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .padding()
            .navigationTitle("Profiles")
        }
        .frame(minWidth: 500, minHeight: 340)
    }
}

private struct SettingsSheetView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Toggle("Show compact tab strip", isOn: Binding(
                        get: { viewModel.sessionSettings.showCompactTabStrip },
                        set: { viewModel.setShowCompactTabStrip($0) }
                    ))
                }

                Section("Session") {
                    Toggle("Restore previous session", isOn: Binding(
                        get: { viewModel.sessionSettings.restorePreviousSession },
                        set: { viewModel.setRestorePreviousSessionEnabled($0) }
                    ))
                    Toggle("Include private tabs in session", isOn: Binding(
                        get: { viewModel.sessionSettings.includePrivateTabsInSession },
                        set: { viewModel.setIncludePrivateTabsInSession($0) }
                    ))
                }

                Section("Autofill troubleshooting") {
                    Text("Pine uses WebKit and macOS Password AutoFill. If AutoFill or passkeys are not appearing, check System Settings > Passwords and verify AutoFill is enabled for passwords and passkeys.")
                        .font(.subheadline)
                    Text("Some sites only show AutoFill after selecting a username/password field directly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Site Permissions Defaults") {
                    Toggle("Block pop-ups by default", isOn: Binding(
                        get: { viewModel.permissionDefaults.blockPopupsByDefault },
                        set: { viewModel.setBlockPopupsByDefault($0) }
                    ))
                    Toggle("Ask for camera and microphone always", isOn: Binding(
                        get: { viewModel.permissionDefaults.askForCameraAndMicrophoneAlways },
                        set: { viewModel.setAskCameraAndMicrophoneAlways($0) }
                    ))
                }

                Section("Privacy") {
                    Picker("Tracker blocking", selection: Binding(
                        get: { viewModel.trackerBlockingMode },
                        set: { viewModel.setTrackerBlockingMode($0) }
                    )) {
                        ForEach(TrackerBlockingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text("Basic mode uses a conservative built-in WebKit rule list to block common third-party trackers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Developer") {
                    Toggle("Enable Web Inspector in debug builds", isOn: Binding(
                        get: { viewModel.sessionSettings.enableWebInspectorInDebugBuilds },
                        set: { viewModel.setEnableWebInspectorInDebugBuilds($0) }
                    ))
                    Toggle("Enable Web Inspector in release builds", isOn: Binding(
                        get: { viewModel.sessionSettings.enableWebInspectorInReleaseBuilds },
                        set: { viewModel.setEnableWebInspectorInReleaseBuilds($0) }
                    ))
                    Text("Release build inspector access is optional and off by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Downloads") {
                    Toggle("Ask where to save each file", isOn: Binding(
                        get: { viewModel.downloadManager.askWhereToSaveEachFile },
                        set: { viewModel.downloadManager.setAskWhereToSaveEachFile($0) }
                    ))

                    if !viewModel.downloadManager.askWhereToSaveEachFile {
                        HStack {
                            Text(viewModel.downloadManager.defaultDownloadFolder.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button("Choose Folder...") {
                                viewModel.downloadManager.pickDefaultDownloadFolder()
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 360)
    }
}

#Preview {
    BrowserRootView()
}
