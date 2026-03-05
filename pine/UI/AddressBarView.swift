import AppKit
import SwiftUI

struct AddressBarView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @State private var addressInput = ""
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

    private func submitAddressBar() {
        viewModel.loadSelectedTab(from: addressInput)
    }
}

#Preview {
    AddressBarView(viewModel: BrowserViewModel())
}
