import SwiftUI

struct AddressBarView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @FocusState private var isAddressFieldFocused: Bool

    private var urlBinding: Binding<String> {
        Binding(
            get: {
                guard
                    let selectedTabID = viewModel.selectedTabID,
                    let index = viewModel.tabs.firstIndex(where: { $0.id == selectedTabID })
                else {
                    return ""
                }

                return viewModel.tabs[index].urlString
            },
            set: { newValue in
                guard
                    let selectedTabID = viewModel.selectedTabID,
                    let index = viewModel.tabs.firstIndex(where: { $0.id == selectedTabID })
                else {
                    return
                }

                viewModel.tabs[index].urlString = newValue
            }
        )
    }

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

            TextField("Enter URL", text: urlBinding)
                .textFieldStyle(.roundedBorder)
                .focused($isAddressFieldFocused)
                .onSubmit {
                    viewModel.loadSelectedTab()
                }

            Button("Go") {
                viewModel.loadSelectedTab()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .onChange(of: viewModel.addressBarFocusToken) { _ in
            isAddressFieldFocused = true
        }
    }
}

#Preview {
    AddressBarView(viewModel: BrowserViewModel())
}
