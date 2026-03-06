import AppKit
import SwiftUI

struct AddressBarView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Binding var addressInput: String
    var addressFieldFocus: FocusState<Bool>.Binding
    let submitAddressBar: () -> Void

    var body: some View {
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
                .onTapGesture {
                    addressFieldFocus.wrappedValue = true
                    DispatchQueue.main.async {
                        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    }
                }
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

    private var selectedFavicon: NSImage? {
        guard let faviconData = viewModel.activeTab?.faviconData else { return nil }
        return NSImage(data: faviconData)
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

