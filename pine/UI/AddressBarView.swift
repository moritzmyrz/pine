import SwiftUI

struct AddressBarView: View {
    @ObservedObject var viewModel: BrowserViewModel

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
            TextField("Enter URL", text: urlBinding)
                .textFieldStyle(.roundedBorder)

            Button("Go") {
                guard
                    let selectedTabID = viewModel.selectedTabID,
                    let tab = viewModel.tabs.first(where: { $0.id == selectedTabID })
                else {
                    return
                }

                print("Go to \(tab.urlString)")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }
}

#Preview {
    AddressBarView(viewModel: BrowserViewModel())
}
