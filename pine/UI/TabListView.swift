import AppKit
import SwiftUI

struct TabListView: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(viewModel.sortedTabs) { tab in
                    tabRow(for: tab)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func tabRow(for tab: Tab) -> some View {
        HStack(spacing: 8) {
            if let image = favicon(for: tab) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }

            Text(tab.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if tab.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                viewModel.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Close Tab")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tab.id == viewModel.activeTab?.id ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectTab(id: tab.id)
        }
    }

    private func favicon(for tab: Tab) -> NSImage? {
        guard let faviconData = tab.faviconData else { return nil }
        return NSImage(data: faviconData)
    }
}
