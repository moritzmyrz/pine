import SwiftUI

struct BrowserRootView: View {
    @StateObject private var viewModel = BrowserViewModel()

    var body: some View {
        VStack(spacing: 0) {
            AddressBarView(viewModel: viewModel)
            Divider()
            tabStrip
            Divider()

            VStack {
                Spacer()
                Text("WebView goes here")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.tabs) { tab in
                    HStack(spacing: 6) {
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
                    viewModel.newTab()
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
