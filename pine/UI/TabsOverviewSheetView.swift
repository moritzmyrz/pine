import AppKit
import SwiftUI

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
