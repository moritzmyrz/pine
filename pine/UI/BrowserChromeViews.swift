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
            backButton
            forwardButton
            reloadStopButton
            addressField
            siteSettingsButton
            tabsButton
            overflowMenu
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var backButton: some View {
        Button {
            viewModel.goBackSelectedTab()
        } label: {
            Image(systemName: "chevron.left")
        }
        .disabled(!(viewModel.activeTab?.canGoBack ?? false))
        .help("Back")
    }

    private var forwardButton: some View {
        Button {
            viewModel.goForwardSelectedTab()
        } label: {
            Image(systemName: "chevron.right")
        }
        .disabled(!(viewModel.activeTab?.canGoForward ?? false))
        .help("Forward")
    }

    private var reloadStopButton: some View {
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

    private var addressField: some View {
        HStack(spacing: 6) {
            if let favicon = selectedFavicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }

            TextField("Search or enter website name", text: $addressInput)
                .textFieldStyle(.plain)
                .focused(addressFieldFocus)
                .onSubmit {
                    submitAddressBar()
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .frame(maxWidth: .infinity)
    }

    private var siteSettingsButton: some View {
        Button {
            isSiteSettingsPresented = true
        } label: {
            Image(systemName: siteLockSymbol)
        }
        .disabled(currentHost == nil)
        .help("Site Settings")
        .popover(isPresented: $isSiteSettingsPresented, arrowEdge: .bottom) {
            SiteSettingsPopoverView(viewModel: viewModel)
        }
    }

    private var tabsButton: some View {
        Button {
            isTabsOverviewPresented = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.on.square")
                Text("\(viewModel.tabs.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .help("Tabs Overview")
    }

    private var overflowMenu: some View {
        Menu {
            Button("History") {
                viewModel.store.isHistoryPresented = true
            }
            Button("Bookmarks") {
                viewModel.store.isBookmarksPresented = true
            }
            Button("Downloads") {
                viewModel.downloadController.showDownloadsSheet()
            }
            Button("Settings") {
                viewModel.store.isSettingsPresented = true
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
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 20)
        }
        .help("Menu")
    }

    private var selectedFavicon: NSImage? {
        guard let data = viewModel.activeTab?.faviconData else { return nil }
        return NSImage(data: data)
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

