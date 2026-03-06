import AppKit
import SwiftUI

struct BrowserTopBar: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Binding var addressInput: String
    var addressFieldFocus: FocusState<Bool>.Binding
    @Binding var isSiteSettingsPresented: Bool
    @Binding var isTabsOverviewPresented: Bool
    let submitAddressBar: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            BrowserNavigationControls(viewModel: viewModel)
                .controlSize(.small)
            AddressBarView(
                viewModel: viewModel,
                addressInput: $addressInput,
                addressFieldFocus: addressFieldFocus,
                submitAddressBar: submitAddressBar
            )
            SiteSettingsButton(
                viewModel: viewModel,
                isPresented: $isSiteSettingsPresented
            )
            TabsOverviewButton(
                tabCount: viewModel.tabs.count,
                isPresented: $isTabsOverviewPresented
            )
            BrowserOverflowMenu(
                viewModel: viewModel,
                isTabsOverviewPresented: $isTabsOverviewPresented
            )
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }
}

struct BrowserSidebarChrome: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Binding var addressInput: String
    var addressFieldFocus: FocusState<Bool>.Binding
    @Binding var isSiteSettingsPresented: Bool
    @Binding var isTabsOverviewPresented: Bool
    let submitAddressBar: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            BrowserNavigationControls(viewModel: viewModel)
                .controlSize(.small)

            AddressBarView(
                viewModel: viewModel,
                addressInput: $addressInput,
                addressFieldFocus: addressFieldFocus,
                submitAddressBar: submitAddressBar
            )
            .controlSize(.small)

            HStack(spacing: 8) {
                SiteSettingsButton(
                    viewModel: viewModel,
                    isPresented: $isSiteSettingsPresented
                )
                TabsOverviewButton(
                    tabCount: viewModel.tabs.count,
                    isPresented: $isTabsOverviewPresented
                )
                Button {
                    viewModel.newTab(focusAddressBar: true)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 18)
                }
                .help("New Tab")

                Spacer(minLength: 0)

                BrowserOverflowMenu(
                    viewModel: viewModel,
                    isTabsOverviewPresented: $isTabsOverviewPresented
                )
            }
            .controlSize(.small)

            Divider()

            TabListView(viewModel: viewModel)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }
}

private struct SiteSettingsButton: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: siteLockSymbol)
        }
        .disabled(currentHost == nil)
        .help("Site Settings")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SiteSettingsPopoverView(viewModel: viewModel)
        }
    }

    private var currentHost: String? {
        viewModel.currentSiteHost()
    }

    private var siteLockSymbol: String {
        guard let urlString = viewModel.activeTab?.urlString,
              let scheme = URL(string: urlString)?.scheme?.lowercased() else {
            return "lock.open"
        }
        return scheme == "https" ? "lock" : "lock.open"
    }
}

private struct TabsOverviewButton: View {
    let tabCount: Int
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.on.square")
                Text("\(tabCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .help("Tabs Overview")
    }
}

private struct BrowserNavigationControls: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.goBackSelectedTab()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!(viewModel.activeTab?.canGoBack ?? false))
            .help("Back")

            Button {
                viewModel.goForwardSelectedTab()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!(viewModel.activeTab?.canGoForward ?? false))
            .help("Forward")

            Button {
                if viewModel.activeTab?.isLoading == true {
                    viewModel.stopLoadingSelectedTab()
                } else {
                    viewModel.reloadSelectedTab()
                }
            } label: {
                Image(systemName: (viewModel.activeTab?.isLoading == true) ? "xmark" : "arrow.clockwise")
            }
            .help((viewModel.activeTab?.isLoading == true) ? "Stop Loading" : "Reload")
        }
    }
}

private struct BrowserOverflowMenu: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Binding var isTabsOverviewPresented: Bool

    var body: some View {
        Menu {
            Button("History") {
                viewModel.showHistory()
            }
            Button("Bookmarks") {
                viewModel.showBookmarks()
            }
            Button("Downloads") {
                viewModel.showDownloads()
            }
            Button("Settings") {
                viewModel.showSettings()
            }

            Divider()

            Button("Open in Safari") {
                viewModel.openSelectedPageInSafari()
            }
            Button("Copy Clean URL") {
                viewModel.copyCleanLinkForSelectedTab()
            }

            Divider()

            Button("New Tab") {
                viewModel.newTab(focusAddressBar: true)
            }
            Button("New Private Tab") {
                viewModel.newPrivateTab(focusAddressBar: true)
            }
            Button("Close Tab") {
                viewModel.closeCurrentTab()
            }
            Button("Reopen Closed Tab") {
                viewModel.reopenClosedTab()
            }

            Divider()

            Button(viewModel.isCurrentPageBookmarked() ? "Remove Bookmark" : "Add Bookmark") {
                viewModel.toggleBookmarkForSelectedTab()
            }
            Menu("Layout") {
                Picker("Layout", selection: Binding(
                    get: { viewModel.sessionSettings.layoutStyle },
                    set: { viewModel.setLayoutStyle($0) }
                )) {
                    ForEach(LayoutStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            }
            Button(viewModel.sessionSettings.showBookmarksBar ? "Hide Bookmark Bar" : "Show Bookmark Bar") {
                viewModel.toggleBookmarksBar()
            }
            Button("View Source") {
                viewModel.viewSourceForSelectedTab()
            }

            Menu("Reading") {
                Button("Zoom In") { viewModel.zoomInSelectedTab() }
                Button("Zoom Out") { viewModel.zoomOutSelectedTab() }
                Button("Actual Size") { viewModel.resetZoomSelectedTab() }
                Divider()
                Button(readerModeButtonTitle) { viewModel.toggleReaderModeForSelectedTab() }
            }

            Menu("Session") {
                Button(restoreSessionMenuTitle) {
                    viewModel.setRestorePreviousSessionEnabled(!viewModel.sessionSettings.restorePreviousSession)
                }
                Button(includePrivateTabsMenuTitle) {
                    viewModel.setIncludePrivateTabsInSession(!viewModel.sessionSettings.includePrivateTabsInSession)
                }
            }

            Menu("Profiles") {
                Picker("Current Profile", selection: Binding(
                    get: { viewModel.currentProfileID },
                    set: { viewModel.selectProfile(id: $0) }
                )) {
                    ForEach(viewModel.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                Divider()
                Button("Manage Profiles...") {
                    viewModel.store.isProfileManagementPresented = true
                }
            }

            Menu("Workspaces") {
                Button("Save Current Tabs as Workspace") {
                    _ = viewModel.createWorkspaceFromCurrentTabs(named: nil)
                }
                .disabled(!viewModel.hasSavableTabsForWorkspace)

                Divider()

                if viewModel.workspaces.isEmpty {
                    Text("No workspaces yet")
                } else {
                    ForEach(viewModel.workspaces) { workspace in
                        Button {
                            viewModel.switchToWorkspace(id: workspace.id)
                        } label: {
                            if workspace.id == viewModel.currentWorkspaceID {
                                Label(workspace.name, systemImage: "checkmark")
                            } else {
                                Text(workspace.name)
                            }
                        }
                    }
                }

                Divider()

                Button("Manage Workspaces...") {
                    isTabsOverviewPresented = true
                }
            }

            Divider()

            Button(viewModel.isSplitViewEnabled ? "Disable Split View" : "Enable Split View") {
                viewModel.toggleSplitView()
            }

            Button("Swap Split Panes") {
                viewModel.swapSplitPanes()
            }
            .disabled(!viewModel.isSplitViewEnabled)

            Divider()

            Button(viewModel.sessionSettings.showCompactTabStrip ? "Hide Tab Strip" : "Show Tab Strip") {
                viewModel.setShowCompactTabStrip(!viewModel.sessionSettings.showCompactTabStrip)
            }
            .disabled(viewModel.sessionSettings.layoutStyle == .sidebar)

            Button(viewModel.sessionSettings.zenModeKeepsSidebar ? "Zen Mode Hides Sidebar" : "Zen Mode Keeps Sidebar") {
                viewModel.setZenModeKeepsSidebar(!viewModel.sessionSettings.zenModeKeepsSidebar)
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 20)
        }
        .help("Menu")
    }

    private var readerModeButtonTitle: String {
        (viewModel.activeTab?.isReaderModeEnabled == true) ? "Disable Reader Mode (Lite)" : "Enable Reader Mode (Lite)"
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

