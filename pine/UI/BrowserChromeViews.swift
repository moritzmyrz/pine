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
        .disabled(!(viewModel.selectedTab?.canGoBack ?? false))
        .help("Back")
    }

    private var forwardButton: some View {
        Button {
            viewModel.goForwardSelectedTab()
        } label: {
            Image(systemName: "chevron.right")
        }
        .disabled(!(viewModel.selectedTab?.canGoForward ?? false))
        .help("Forward")
    }

    private var reloadStopButton: some View {
        Button {
            if viewModel.selectedTab?.isLoading == true {
                viewModel.stopLoadingSelectedTab()
            } else {
                viewModel.reloadSelectedTab()
            }
        } label: {
            Image(systemName: (viewModel.selectedTab?.isLoading == true) ? "xmark" : "arrow.clockwise")
        }
        .help((viewModel.selectedTab?.isLoading == true) ? "Stop Loading" : "Reload")
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
        guard let data = viewModel.selectedTab?.faviconData else { return nil }
        return NSImage(data: data)
    }

    private var currentHost: String? {
        viewModel.currentSiteHost()
    }

    private var siteLockSymbol: String {
        guard let urlString = viewModel.selectedTab?.urlString,
              let scheme = URL(string: urlString)?.scheme?.lowercased() else {
            return "lock.open"
        }
        return scheme == "https" ? "lock" : "lock.open"
    }

    private var readerModeButtonTitle: String {
        (viewModel.selectedTab?.isReaderModeEnabled == true) ? "Disable Reader Mode (Lite)" : "Enable Reader Mode (Lite)"
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

struct TabsOverviewSheetView: View {
    enum LayoutMode: String, CaseIterable, Identifiable {
        case list
        case grid

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    @ObservedObject var viewModel: BrowserViewModel

    @State private var query = ""
    @State private var layoutMode: LayoutMode = .list
    @State private var selectedWorkspaceID: UUID?
    @State private var isCreateWorkspacePromptPresented = false
    @State private var isRenameWorkspacePromptPresented = false
    @State private var newWorkspaceName = ""
    @State private var renameWorkspaceInput = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HSplitView {
                workspaceSidebar
                    .frame(minWidth: 220, maxWidth: 260)

                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        TextField("Search tabs", text: $query)
                            .textFieldStyle(.roundedBorder)
                        Picker("Layout", selection: $layoutMode) {
                            ForEach(LayoutMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }

                    if filteredTabs.isEmpty {
                        ContentUnavailableView(
                            "No Matching Tabs",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different title or URL.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if layoutMode == .list {
                        List(filteredTabs) { tab in
                            tabListRow(tab)
                        }
                        .listStyle(.inset)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 10)], spacing: 10) {
                                ForEach(filteredTabs) { tab in
                                    tabGridCard(tab)
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }
            .navigationTitle("Tabs Overview")
        }
        .frame(minWidth: 680, minHeight: 420)
        .onAppear {
            selectedWorkspaceID = viewModel.currentWorkspaceID
        }
        .onChange(of: viewModel.currentWorkspaceID) {
            selectedWorkspaceID = viewModel.currentWorkspaceID
        }
        .alert("New Workspace", isPresented: $isCreateWorkspacePromptPresented) {
            TextField("Name", text: $newWorkspaceName)
            Button("Cancel", role: .cancel) {
                newWorkspaceName = ""
            }
            Button("Create") {
                let id = viewModel.createWorkspaceFromCurrentTabs(named: newWorkspaceName)
                if let id {
                    selectedWorkspaceID = id
                }
                newWorkspaceName = ""
            }
            .disabled(!viewModel.hasSavableTabsForWorkspace)
        } message: {
            Text("Private tabs are not included.")
        }
        .alert("Rename Workspace", isPresented: $isRenameWorkspacePromptPresented) {
            TextField("Name", text: $renameWorkspaceInput)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                guard let selectedWorkspaceID else { return }
                viewModel.renameWorkspace(id: selectedWorkspaceID, to: renameWorkspaceInput)
            }
            .disabled(selectedWorkspaceID == nil || renameWorkspaceInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func tabListRow(_ tab: Tab) -> some View {
        HStack(spacing: 10) {
            faviconOrPlaceholder(for: tab, size: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .lineLimit(1)
                Text(tab.urlString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if tab.id == viewModel.selectedTabID {
                Text("Current")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectTab(id: tab.id)
            dismiss()
        }
    }

    private func tabGridCard(_ tab: Tab) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                faviconOrPlaceholder(for: tab, size: 16)
                Text(tab.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    viewModel.closeTab(id: tab.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(tab.urlString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if tab.id == viewModel.selectedTabID {
                Text("Current Tab")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            viewModel.selectTab(id: tab.id)
            dismiss()
        }
    }

    private func faviconOrPlaceholder(for tab: Tab, size: CGFloat) -> some View {
        Group {
            if let data = tab.faviconData, let favicon = NSImage(data: data) {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
    }

    private var filteredTabs: [Tab] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return viewModel.sortedTabs }
        let lowered = trimmed.lowercased()
        return viewModel.sortedTabs.filter { tab in
            tab.title.lowercased().contains(lowered) || tab.urlString.lowercased().contains(lowered)
        }
    }

    private var workspaceSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Workspaces")
                    .font(.headline)
                Spacer(minLength: 0)
                Button {
                    newWorkspaceName = ""
                    isCreateWorkspacePromptPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Create workspace from current tabs")
                .disabled(!viewModel.hasSavableTabsForWorkspace)
            }

            if viewModel.workspaces.isEmpty {
                ContentUnavailableView(
                    "No Workspaces",
                    systemImage: "tray",
                    description: Text("Save your current non-private tabs as a workspace.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.workspaces) { workspace in
                    Button {
                        selectedWorkspaceID = workspace.id
                        viewModel.switchToWorkspace(id: workspace.id)
                    } label: {
                        HStack(spacing: 8) {
                            Text(workspace.name)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if workspace.id == viewModel.currentWorkspaceID {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Switch") {
                            selectedWorkspaceID = workspace.id
                            viewModel.switchToWorkspace(id: workspace.id)
                        }
                        Button("Rename") {
                            selectedWorkspaceID = workspace.id
                            renameWorkspaceInput = workspace.name
                            isRenameWorkspacePromptPresented = true
                        }
                        Button("Delete", role: .destructive) {
                            if selectedWorkspaceID == workspace.id {
                                selectedWorkspaceID = nil
                            }
                            viewModel.deleteWorkspace(id: workspace.id)
                        }
                    }
                }
                .listStyle(.sidebar)
            }

            HStack(spacing: 8) {
                Button("Rename") {
                    guard let selectedWorkspaceID,
                          let selectedWorkspace = viewModel.workspaces.first(where: { $0.id == selectedWorkspaceID }) else { return }
                    renameWorkspaceInput = selectedWorkspace.name
                    isRenameWorkspacePromptPresented = true
                }
                .disabled(selectedWorkspaceID == nil)

                Button("Delete", role: .destructive) {
                    guard let selectedWorkspaceID else { return }
                    viewModel.deleteWorkspace(id: selectedWorkspaceID)
                    self.selectedWorkspaceID = nil
                }
                .disabled(selectedWorkspaceID == nil)
            }
            .font(.caption)

            Text("Private tabs are never saved into workspaces.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 14)
        .padding(.leading, 14)
        .padding(.bottom, 14)
    }
}
