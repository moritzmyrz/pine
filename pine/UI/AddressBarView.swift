import AppKit
import SwiftUI

struct AddressBarView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var addressInput = ""
    @State private var isSiteSettingsPresented = false
    @FocusState private var isAddressFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.goBackSelectedTab()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!(viewModel.selectedTab?.canGoBack ?? false))

            Button {
                viewModel.goForwardSelectedTab()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!(viewModel.selectedTab?.canGoForward ?? false))

            Button {
                viewModel.reloadSelectedTab()
            } label: {
                Image(systemName: "arrow.clockwise")
            }

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

            Button {
                isSiteSettingsPresented = true
            } label: {
                Image(systemName: siteLockSymbol)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(currentHost == nil)
            .popover(isPresented: $isSiteSettingsPresented, arrowEdge: .bottom) {
                SiteSettingsPopoverView(viewModel: viewModel)
            }

            TextField("Enter URL", text: $addressInput)
                .textFieldStyle(.roundedBorder)
                .focused($isAddressFieldFocused)
                .onSubmit {
                    submitAddressBar()
                }

            Button("Go") {
                submitAddressBar()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
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

    private var currentTabURL: String {
        viewModel.selectedTab?.urlString ?? ""
    }

    private var selectedFavicon: NSImage? {
        guard let faviconData = viewModel.selectedTab?.faviconData else { return nil }
        return NSImage(data: faviconData)
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

    private func submitAddressBar() {
        viewModel.loadSelectedTab(from: addressInput)
    }
}

struct SiteSettingsPopoverView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var didClearData = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Site Settings")
                .font(.headline)

            Text(currentHost ?? "No site")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Divider()

            if let host = currentHost {
                ForEach(SitePermissionType.allCases) { permissionType in
                    HStack {
                        Text(permissionType.title)
                            .font(.subheadline)
                        Spacer()
                        Picker(permissionType.title, selection: Binding(
                            get: { viewModel.permissionValue(for: permissionType, host: host) },
                            set: { viewModel.setPermissionValue($0, for: permissionType, host: host) }
                        )) {
                            ForEach(SitePermissionValue.allCases, id: \.self) { value in
                                Text(value.title).tag(value)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 100)
                    }
                }

                Divider()

                Button("Clear Site Data") {
                    viewModel.clearWebsiteData(for: host) {
                        didClearData = true
                    }
                }

                if didClearData {
                    Text("Site data cleared.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Open a website to edit permissions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private var currentHost: String? {
        viewModel.currentSiteHost()
    }
}

#Preview {
    AddressBarView(viewModel: BrowserViewModel())
}
