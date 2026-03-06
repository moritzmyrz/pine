import AppKit
import SwiftUI

struct BrowserRootView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel: BrowserViewModel
    @StateObject private var commandPaletteViewModel: CommandPaletteViewModel
    @StateObject private var addressBarViewModel: AddressBarViewModel
    @State private var draggedTabID: UUID?
    @State private var observedWindowNumber: Int?
    @State private var isSiteSettingsPresented = false
    @State private var shouldRestoreAddressFocusAfterPalette = false
    @FocusState private var isAddressFieldFocused: Bool

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

                browserContentArea

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
        BrowserCompactTabStripView(
            viewModel: viewModel,
            draggedTabID: $draggedTabID
        )
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

#Preview {
    BrowserRootView()
}
