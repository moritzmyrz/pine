import SwiftUI

struct HistorySheetView: View {
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

struct BookmarksSheetView: View {
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

struct DownloadsSheetView: View {
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

struct DownloadsShelfView: View {
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

struct ProfileManagementSheet: View {
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

struct SettingsSheetView: View {
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

                Section("Address Bar") {
                    Toggle("Always show full URL", isOn: Binding(
                        get: { viewModel.sessionSettings.alwaysShowFullURLInAddressBar },
                        set: { viewModel.setAlwaysShowFullURLInAddressBar($0) }
                    ))

                    Toggle("Hide https://", isOn: Binding(
                        get: { viewModel.sessionSettings.hideHTTPSInAddressBar },
                        set: { viewModel.setHideHTTPSInAddressBar($0) }
                    ))
                    .disabled(viewModel.sessionSettings.alwaysShowFullURLInAddressBar)

                    Toggle("Hide www.", isOn: Binding(
                        get: { viewModel.sessionSettings.hideWWWInAddressBar },
                        set: { viewModel.setHideWWWInAddressBar($0) }
                    ))
                    .disabled(viewModel.sessionSettings.alwaysShowFullURLInAddressBar)
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
