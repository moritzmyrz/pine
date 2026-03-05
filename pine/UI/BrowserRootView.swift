import SwiftUI

struct BrowserRootView: View {
    @StateObject private var viewModel = BrowserViewModel()

    var body: some View {
        VStack(spacing: 0) {
            AddressBarView(viewModel: viewModel)
            Divider()
            tabStrip
            Divider()

            if let selectedTabID = viewModel.selectedTabID {
                WebViewContainer(viewModel: viewModel, tabID: selectedTabID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Spacer()
                    Text("No tab selected")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("New Tab") {
                    viewModel.newTab(focusAddressBar: true)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    viewModel.closeCurrentTab()
                }
                .keyboardShortcut("w", modifiers: .command)
            }
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.tabs) { tab in
                    HStack(spacing: 6) {
                        if tab.isLoading {
                            Text("...")
                                .foregroundStyle(.secondary)
                        }

                        Text(tab.title)
                            .lineLimit(1)

                        Button {
                            viewModel.closeTab(id: tab.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tab.id == viewModel.selectedTabID ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        viewModel.selectTab(id: tab.id)
                    }
                }

                Button {
                    viewModel.newTab(focusAddressBar: true)
                } label: {
                    Image(systemName: "plus")
                        .padding(6)
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
        }
    }
}

#Preview {
    BrowserRootView()
}
