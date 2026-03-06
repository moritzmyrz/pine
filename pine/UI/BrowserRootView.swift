import AppKit
import SwiftUI

struct BrowserRootView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel: BrowserViewModel
    @StateObject private var commandPaletteViewModel: CommandPaletteViewModel
    @StateObject private var addressBarViewModel: AddressBarViewModel
    @State private var observedWindowNumber: Int?
    @State private var isSiteSettingsPresented = false
    @State private var shouldRestoreAddressFocusAfterPalette = false
    @FocusState private var isAddressFieldFocused: Bool
    private let snapHoverController = TabSnapHoverController()

    init() {
        let sharedStores = SharedStores.shared
        let browserViewModel = BrowserViewModel(
            shouldRestoreSession: WindowLaunchState.consumeShouldRestoreSession(),
            historyStore: sharedStores.historyStore,
            bookmarksStore: sharedStores.bookmarksStore,
            downloadManager: sharedStores.downloadManager
        )
        _viewModel = StateObject(wrappedValue: browserViewModel)
        _commandPaletteViewModel = StateObject(
            wrappedValue: CommandPaletteViewModel(browserViewModel: browserViewModel)
        )
        _addressBarViewModel = StateObject(wrappedValue: AddressBarViewModel())
    }

    var body: some View {
        configuredRootView
    }

    private var configuredRootView: some View {
        rootLayout
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
            .background(
                WindowObserver { window in
                    handleWindowChange(window)
                    viewModel.onRequestWindowClose = { [weak window] in
                        if let window {
                            window.performClose(nil)
                        } else {
                            NSApp.keyWindow?.performClose(nil)
                        }
                    }
                }
            )
            .onDisappear {
                if let observedWindowNumber {
                    BrowserWindowManager.shared.unregister(windowNumber: observedWindowNumber)
                }
                observedWindowNumber = nil
                viewModel.setTargetWindowNumber(nil)
                viewModel.onRequestWindowClose = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .pineOpenLibrary)) { notification in
                let keyOrMainWindowNumber = NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber
                guard keyOrMainWindowNumber == observedWindowNumber else { return }

                if let rawSection = notification.userInfo?[LibraryCommandUserInfoKey.section] as? String,
                   let section = LibrarySection(rawValue: rawSection) {
                    LibraryNavigationState.shared.open(section)
                }
                openWindow(id: "pine-library")
            }
    }

    private var rootLayout: some View {
        let zenStyle = ZenModeStyle(
            isZenModeEnabled: viewModel.isZenModeEnabled,
            hideToolbarInZenMode: viewModel.sessionSettings.zenModeHidesToolbar
        )

        return ZStack {
            VStack(spacing: 0) {
                if !zenStyle.shouldHideToolbar {
                    BrowserTopBar(
                        viewModel: viewModel,
                        addressInput: addressBarInputBinding,
                        addressFieldFocus: $isAddressFieldFocused,
                        isSiteSettingsPresented: siteSettingsPresentedBinding,
                        isTabsOverviewPresented: tabsOverviewSheetBinding,
                        submitAddressBar: submitAddressBar
                    )
                    loadingProgressBar
                }

                if viewModel.sessionSettings.showCompactTabStrip, !zenStyle.shouldHideTabStrip {
                    Divider()
                    tabStrip
                }

                if viewModel.sessionSettings.showBookmarksBar, !zenStyle.shouldHideBookmarksBar {
                    Divider()
                    BookmarksBarView(viewModel: viewModel)
                }

                GeometryReader { geometry in
                    browserContentArea
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay {
                            if viewModel.store.isDraggingTab {
                                ContentAreaDragDestinationView(
                                    onDragMove: { location in
                                        let side = snapHoverController.splitSide(for: location, in: geometry.size)
                                        viewModel.updateTabDropContext(targetTabID: nil, splitSide: side)
                                    },
                                    onDragExit: {
                                        viewModel.updateTabDropContext(targetTabID: nil, splitSide: .none)
                                    },
                                    onDrop: { location in
                                        let side = snapHoverController.splitSide(for: location, in: geometry.size)
                                        viewModel.dropDraggedTabOnContent(splitSide: side)
                                        return true
                                    }
                                )
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }
                        .overlay {
                            TabSnapPreviewOverlayView(
                                hoveredSide: contentSnapPreviewSide,
                                draggedTab: draggedTab,
                                anchorTab: snapAnchorTab
                            )
                        }
                }

                if viewModel.downloadController.shouldShowShelf, !zenStyle.shouldHideDownloadsShelf {
                    Divider()
                    DownloadsShelfView(
                        downloadManager: viewModel.downloadManager,
                        openDownloadsSheet: { viewModel.showDownloads() },
                        closeShelf: { viewModel.downloadController.dismissShelf() }
                    )
                }
            }
            .background {
                shortcutButtons
            }

            CommandPaletteView(viewModel: commandPaletteViewModel)
                .animation(.easeOut(duration: 0.15), value: commandPaletteViewModel.isPresented)
        }
        .onAppear {
            addressBarViewModel.initialize(activeTab: viewModel.activeTab, settings: viewModel.sessionSettings)
        }
        .onChange(of: activeTabIdentity) {
            addressBarViewModel.didSelectActiveTab(viewModel.activeTab, settings: viewModel.sessionSettings)
        }
        .onChange(of: activeTabSnapshot) {
            addressBarViewModel.didUpdateActiveTab(viewModel.activeTab, settings: viewModel.sessionSettings)
        }
        .onChange(of: isAddressFieldFocused) {
            addressBarViewModel.didChangeFocus(
                isFocused: isAddressFieldFocused,
                activeURLString: currentTabURL,
                settings: viewModel.sessionSettings
            )

            guard isAddressFieldFocused else { return }
            DispatchQueue.main.async {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
        .onChange(of: addressDisplaySettingsSignature) {
            addressBarViewModel.didChangeDisplaySettings(
                activeURLString: currentTabURL,
                settings: viewModel.sessionSettings
            )
        }
        .onChange(of: viewModel.addressBarFocusToken) {
            isAddressFieldFocused = true
            DispatchQueue.main.async {
                if viewModel.shouldSelectAllInAddressBar {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    viewModel.consumeAddressBarSelectAllRequest()
                }
            }
        }
        .onChange(of: commandPaletteViewModel.isPresented) {
            if commandPaletteViewModel.isPresented {
                shouldRestoreAddressFocusAfterPalette = isAddressFieldFocused
                isAddressFieldFocused = false
                return
            }

            DispatchQueue.main.async {
                if shouldRestoreAddressFocusAfterPalette {
                    viewModel.requestAddressBarFocus(selectAll: false)
                } else {
                    viewModel.focusActiveWebViewIfPossible()
                }
            }
        }
    }

    private var shortcutButtons: some View {
        VStack {
            Button("Focus Address") {
                viewModel.requestAddressBarFocus(selectAll: true)
            }
            .keyboardShortcut("l", modifiers: .command)
            .hidden()

            Button("Toggle Command Palette") {
                commandPaletteViewModel.toggle()
            }
            .keyboardShortcut("k", modifiers: .command)
            .hidden()

            Button("Toggle Zen Mode") {
                viewModel.toggleZenMode()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .hidden()

            if viewModel.isZenModeEnabled && viewModel.sessionSettings.escExitsZenMode {
                Button("Exit Zen Mode") {
                    viewModel.exitZenMode()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
            }
        }
    }

    @ViewBuilder
    private var browserContentArea: some View {
        if viewModel.isSplitViewEnabled, splitPaneIDs.count >= 2 {
            multiPaneLayout(tabIDs: splitPaneIDs)
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

    private func multiPaneLayout(tabIDs: [UUID]) -> some View {
        Group {
            if tabIDs.count == 2 {
                twoPaneLayout(primaryTabID: tabIDs[0], secondaryTabID: tabIDs[1])
            } else {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        if viewModel.store.splitLayout == .horizontal {
                            let paneHeight = geometry.size.height / CGFloat(max(tabIDs.count, 1))
                            VStack(spacing: 0) {
                                ForEach(Array(tabIDs.enumerated()), id: \.element) { _, tabID in
                                    paneContainer(tabID: tabID)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: paneHeight)
                                    if tabID != tabIDs.last {
                                        Divider()
                                    }
                                }
                            }
                        } else {
                            let paneWidth = geometry.size.width / CGFloat(max(tabIDs.count, 1))
                            HStack(spacing: 0) {
                                ForEach(Array(tabIDs.enumerated()), id: \.element) { _, tabID in
                                    paneContainer(tabID: tabID)
                                        .frame(width: paneWidth)
                                        .frame(maxHeight: .infinity)
                                    if tabID != tabIDs.last {
                                        Divider()
                                    }
                                }
                            }
                        }

                        if !viewModel.isZenModeEnabled {
                            SplitViewControls(
                                viewModel: viewModel,
                                primaryTabID: tabIDs[0],
                                secondaryTabID: tabIDs[1]
                            )
                            .padding(8)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func twoPaneLayout(primaryTabID: UUID, secondaryTabID: UUID) -> some View {
        GeometryReader { geometry in
            let dividerWidth: CGFloat = 8
            let availableWidth = max(geometry.size.width - dividerWidth, 1)
            let availableHeight = max(geometry.size.height - dividerWidth, 1)
            let primaryWidth = availableWidth * viewModel.splitRatio
            let secondaryWidth = availableWidth - primaryWidth
            let primaryHeight = availableHeight * viewModel.splitRatio
            let secondaryHeight = availableHeight - primaryHeight

            if viewModel.store.splitLayout == .horizontal {
                VStack(spacing: 0) {
                    paneContainer(tabID: primaryTabID)
                        .frame(maxWidth: .infinity)
                        .frame(height: primaryHeight)

                    SplitResizeDividerVertical {
                        let draggedRatio = $0 / availableHeight
                        viewModel.setSplitRatio(draggedRatio)
                    }
                    .frame(height: dividerWidth)
                    .frame(maxWidth: .infinity)

                    ZStack(alignment: .topLeading) {
                        paneContainer(tabID: secondaryTabID)
                            .frame(maxWidth: .infinity)
                            .frame(height: secondaryHeight)

                        if !viewModel.isZenModeEnabled {
                            SplitViewControls(
                                viewModel: viewModel,
                                primaryTabID: primaryTabID,
                                secondaryTabID: secondaryTabID
                            )
                            .padding(8)
                        }
                    }
                }
            } else {
                HStack(spacing: 0) {
                    paneContainer(tabID: primaryTabID)
                        .frame(width: primaryWidth)
                        .frame(maxHeight: .infinity)

                    SplitResizeDivider {
                        let draggedRatio = $0 / availableWidth
                        viewModel.setSplitRatio(draggedRatio)
                    }
                    .frame(width: dividerWidth)
                    .frame(maxHeight: .infinity)

                    ZStack(alignment: .topLeading) {
                        paneContainer(tabID: secondaryTabID)
                            .frame(width: secondaryWidth)
                            .frame(maxHeight: .infinity)

                        if !viewModel.isZenModeEnabled {
                            SplitViewControls(
                                viewModel: viewModel,
                                primaryTabID: primaryTabID,
                                secondaryTabID: secondaryTabID
                            )
                            .padding(8)
                        }
                    }
                    .frame(width: secondaryWidth)
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .coordinateSpace(name: "splitContainer")
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
                    viewModel.selectTab(id: tabID)
                }
            )
                .id(tabID)
        }
    }

    private func paneContainer(tabID: UUID) -> some View {
        tabContent(tabID: tabID)
            .overlay {
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        isPaneActive(tabID: tabID) ? Color.accentColor.opacity(0.22) : Color.clear,
                        lineWidth: 1
                    )
            }
            .onTapGesture {
                viewModel.selectTab(id: tabID)
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
        BrowserCompactTabStripView(viewModel: viewModel)
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
            get: { viewModel.store.isTabSearchPresented },
            set: { viewModel.store.isTabSearchPresented = $0 }
        )
    }

    private var addressBarInputBinding: Binding<String> {
        Binding(
            get: { addressBarViewModel.inputText },
            set: { addressBarViewModel.inputText = $0 }
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

    private var draggedTab: Tab? {
        guard let draggedTabID = viewModel.store.draggedTabID else { return nil }
        return viewModel.tabs.first(where: { $0.id == draggedTabID })
    }

    private var snapAnchorTab: Tab? {
        if let selectedTabID = viewModel.selectedTabID,
           selectedTabID != viewModel.store.draggedTabID {
            return viewModel.tabs.first(where: { $0.id == selectedTabID })
        }

        if let splitSecondaryTabID = viewModel.splitSecondaryTabID,
           splitSecondaryTabID != viewModel.store.draggedTabID {
            return viewModel.tabs.first(where: { $0.id == splitSecondaryTabID })
        }

        return viewModel.tabs.first(where: { $0.id != viewModel.store.draggedTabID })
    }

    private var contentSnapPreviewSide: SplitDropSide {
        guard viewModel.store.isDraggingTab else { return .none }
        guard viewModel.store.currentDropTarget == nil else { return .none }
        return viewModel.store.intendedSplitSide
    }

    private var activeTabIdentity: UUID? {
        viewModel.activeTab?.id
    }

    private var activeTabSnapshot: ActiveTabSnapshot {
        ActiveTabSnapshot(
            id: viewModel.activeTab?.id,
            urlString: viewModel.activeTab?.urlString ?? "",
            isLoading: viewModel.activeTab?.isLoading ?? false
        )
    }

    private var addressDisplaySettingsSignature: AddressDisplaySettingsSignature {
        AddressDisplaySettingsSignature(
            hideHTTPS: viewModel.sessionSettings.hideHTTPSInAddressBar,
            hideWWW: viewModel.sessionSettings.hideWWWInAddressBar,
            alwaysShowFullURL: viewModel.sessionSettings.alwaysShowFullURLInAddressBar
        )
    }

    private var splitPaneIDs: [UUID] {
        var ids: [UUID] = []
        if let primaryID = viewModel.splitPrimaryTabID, viewModel.tabs.contains(where: { $0.id == primaryID }) {
            ids.append(primaryID)
        }
        if let secondaryID = viewModel.splitSecondaryTabID,
           !ids.contains(secondaryID),
           viewModel.tabs.contains(where: { $0.id == secondaryID }) {
            ids.append(secondaryID)
        }

        let additionalIDs = viewModel.tabs
            .map(\.id)
            .filter { viewModel.store.splitAdditionalTabIDs.contains($0) }
        for id in additionalIDs where !ids.contains(id) {
            ids.append(id)
        }
        return ids
    }

    private func isPaneActive(tabID: UUID) -> Bool {
        guard viewModel.isSplitViewEnabled else {
            return tabID == viewModel.selectedTabID
        }
        if viewModel.activePane == .secondary {
            return tabID == viewModel.splitSecondaryTabID
        }
        return tabID == viewModel.selectedTabID
    }

    private func submitAddressBar() {
        viewModel.loadSelectedTab(from: addressBarViewModel.inputText)
    }

    private func handleWindowChange(_ window: NSWindow?) {
        let windowNumber = window?.windowNumber
        viewModel.setTargetWindowNumber(windowNumber)

        guard observedWindowNumber != windowNumber else { return }

        if let observedWindowNumber {
            BrowserWindowManager.shared.unregister(windowNumber: observedWindowNumber)
        }
        if let windowNumber {
            BrowserWindowManager.shared.register(windowNumber: windowNumber, viewModel: viewModel)
        }
        observedWindowNumber = windowNumber
    }
}

private struct ActiveTabSnapshot: Equatable {
    let id: UUID?
    let urlString: String
    let isLoading: Bool
}

private struct AddressDisplaySettingsSignature: Equatable {
    let hideHTTPS: Bool
    let hideWWW: Bool
    let alwaysShowFullURL: Bool
}

private enum WindowLaunchState {
    private static var hasCreatedPrimaryWindow = false

    static func consumeShouldRestoreSession() -> Bool {
        guard !hasCreatedPrimaryWindow else { return false }
        hasCreatedPrimaryWindow = true
        return true
    }
}

private struct WindowObserver: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            onWindowChange(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onWindowChange(nsView.window)
        }
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

private struct SplitResizeDividerVertical: View {
    let onDragToY: (CGFloat) -> Void

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .gesture(onDragGesture)
    }

    private var onDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("splitContainer"))
            .onChanged { value in
                onDragToY(value.location.y)
            }
    }
}

#Preview {
    BrowserRootView()
}
