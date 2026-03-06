import SwiftUI

struct LibrarySettingsView: View {
    @StateObject private var windowManager = BrowserWindowManager.shared
    @State private var searchText = ""

    var body: some View {
        Group {
            if let viewModel = windowManager.frontmostBrowserViewModel() {
                LibrarySettingsContent(viewModel: viewModel, searchText: searchText)
            } else {
                ContentUnavailableView(
                    "No Browser Window",
                    systemImage: "gearshape",
                    description: Text("Open a browser window to edit settings.")
                )
            }
        }
        .searchable(text: $searchText, prompt: "Search settings")
        .navigationTitle("Settings")
    }
}

private struct LibrarySettingsContent: View {
    @ObservedObject var viewModel: BrowserViewModel
    let searchText: String

    var body: some View {
        Form {
            if shouldShowSection(keywords: ["appearance", "compact", "tabs", "bookmarks", "bar", "rank", "zen", "escape"]) {
                Section("Appearance") {
                    Toggle("Show compact tab strip", isOn: Binding(
                        get: { viewModel.sessionSettings.showCompactTabStrip },
                        set: { viewModel.setShowCompactTabStrip($0) }
                    ))
                    Toggle("Show bookmark bar", isOn: Binding(
                        get: { viewModel.sessionSettings.showBookmarksBar },
                        set: { viewModel.setShowBookmarksBar($0) }
                    ))
                    Toggle("Zen Mode hides toolbar", isOn: Binding(
                        get: { viewModel.sessionSettings.zenModeHidesToolbar },
                        set: { viewModel.setZenModeHidesToolbar($0) }
                    ))
                    Toggle("Esc exits Zen Mode", isOn: Binding(
                        get: { viewModel.sessionSettings.escExitsZenMode },
                        set: { viewModel.setEscExitsZenMode($0) }
                    ))
                }
            }

            if shouldShowSection(keywords: ["address", "url", "https", "www"]) {
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
            }

            if shouldShowSection(keywords: ["session", "restore", "private"]) {
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
            }

            if shouldShowSection(keywords: ["site", "permissions", "camera", "microphone", "popup"]) {
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
            }

            if shouldShowSection(keywords: ["privacy", "tracker", "blocking"]) {
                Section("Privacy") {
                    Picker("Tracker blocking", selection: Binding(
                        get: { viewModel.trackerBlockingMode },
                        set: { viewModel.setTrackerBlockingMode($0) }
                    )) {
                        ForEach(TrackerBlockingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text("Basic mode uses a conservative WebKit rule list to block common third-party trackers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if shouldShowSection(keywords: ["downloads", "save", "folder"]) {
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

            if shouldShowSection(keywords: ["developer", "inspector", "debug", "release"]) {
                Section("Developer") {
                    Toggle("Enable Web Inspector in debug builds", isOn: Binding(
                        get: { viewModel.sessionSettings.enableWebInspectorInDebugBuilds },
                        set: { viewModel.setEnableWebInspectorInDebugBuilds($0) }
                    ))
                    Toggle("Enable Web Inspector in release builds", isOn: Binding(
                        get: { viewModel.sessionSettings.enableWebInspectorInReleaseBuilds },
                        set: { viewModel.setEnableWebInspectorInReleaseBuilds($0) }
                    ))
                }
            }

            if shouldShowSection(keywords: ["autofill", "password", "passkey"]) {
                Section("Autofill") {
                    Text("Pine uses WebKit and macOS Password AutoFill.")
                        .font(.subheadline)
                    Text("If AutoFill or passkeys are missing, verify System Settings > Passwords.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func shouldShowSection(keywords: [String]) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return keywords.contains { $0.contains(query) } || query.contains("settings")
    }
}
