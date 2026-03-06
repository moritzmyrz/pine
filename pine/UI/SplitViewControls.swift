import AppKit
import SwiftUI

struct SplitViewControls: View {
    @ObservedObject var viewModel: BrowserViewModel
    let primaryTabID: UUID
    let secondaryTabID: UUID

    @State private var isSecondaryPickerPresented = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isSecondaryPickerPresented = true
            } label: {
                HStack(spacing: 6) {
                    faviconOrPlaceholder(for: secondaryTab, size: 14)
                    Text(secondaryTab?.title ?? "Select tab")
                        .lineLimit(1)
                        .frame(maxWidth: 180, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $isSecondaryPickerPresented, arrowEdge: .top) {
                secondaryPickerPopover
            }

            Button("Swap panes") {
                viewModel.swapSplitPanes()
            }
            .buttonStyle(.bordered)

            Button("Exit split view") {
                viewModel.disableSplitView()
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.small)
        .padding(6)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var secondaryPickerPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Right Pane Tab")
                .font(.headline)

            if candidateTabs.isEmpty {
                Text("No tab available.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(candidateTabs) { tab in
                            HStack(spacing: 8) {
                                faviconOrPlaceholder(for: tab, size: 14)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tab.title)
                                        .lineLimit(1)
                                    Text(hostLabel(for: tab))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Button(tab.id == secondaryTabID ? "Selected" : "Select") {
                                    viewModel.setSecondaryTab(id: tab.id)
                                    isSecondaryPickerPresented = false
                                }
                                .buttonStyle(.borderless)
                                .disabled(tab.id == secondaryTabID)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private var candidateTabs: [Tab] {
        viewModel.sortedTabs.filter { $0.id != primaryTabID }
    }

    private var secondaryTab: Tab? {
        viewModel.sortedTabs.first(where: { $0.id == secondaryTabID })
    }

    private func hostLabel(for tab: Tab) -> String {
        URL(string: tab.urlString)?.host ?? tab.urlString
    }

    private func faviconOrPlaceholder(for tab: Tab?, size: CGFloat) -> some View {
        Group {
            if let data = tab?.faviconData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
    }
}
