import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BrowserCompactTabStripView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Binding var draggedTabID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.sortedTabs) { tab in
                    HStack(spacing: 6) {
                        if tab.isPinned {
                            if let favicon = faviconImage(for: tab) {
                                Image(nsImage: favicon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 16, height: 16)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Text(pinnedTabSymbol(for: tab))
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 18, height: 18)
                                    .background(Color.secondary.opacity(0.14))
                                    .clipShape(Circle())
                            }
                        } else {
                            if let favicon = faviconImage(for: tab) {
                                Image(nsImage: favicon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 14, height: 14)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            if tab.isLoading {
                                Text("...")
                                    .foregroundStyle(.secondary)
                            }

                            if tab.isPrivate {
                                Text("Private")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.2))
                                    .clipShape(Capsule())
                            }

                            if viewModel.profiles.count > 1 {
                                Text(viewModel.profileName(for: tab.profileID))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.16))
                                    .clipShape(Capsule())
                            }

                            Text(tab.title)
                                .lineLimit(1)
                        }
                        if !tab.isPinned {
                            Button {
                                viewModel.closeTab(id: tab.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, tab.isPinned ? 8 : 10)
                    .padding(.vertical, 5)
                    .background(tab.id == viewModel.selectedTabID ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        MiddleClickCatcher {
                            viewModel.closeTab(id: tab.id)
                        }
                    }
                    .onTapGesture {
                        viewModel.selectTab(id: tab.id)
                    }
                    .contextMenu {
                        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") {
                            viewModel.setTabPinned(id: tab.id, isPinned: !tab.isPinned)
                        }
                        Button("Duplicate Tab") {
                            viewModel.duplicateTab(id: tab.id)
                        }
                        Divider()
                        Button("Close Other Tabs") {
                            viewModel.closeOtherTabs(keeping: tab.id)
                        }
                        .disabled(viewModel.tabs.count <= 1)
                        Button("Close Tabs to the Right") {
                            viewModel.closeTabsToRight(of: tab.id)
                        }
                        .disabled(isRightMostTab(tab.id))
                    }
                    .onDrag {
                        draggedTabID = tab.id
                        return NSItemProvider(object: tab.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: TabDropDelegate(
                            targetTabID: tab.id,
                            draggedTabID: $draggedTabID,
                            onMove: { draggedID, targetID in
                                viewModel.reorderTab(draggedID: draggedID, before: targetID)
                            }
                        )
                    )
                }

                Button {
                    viewModel.newTab(focusAddressBar: true)
                } label: {
                    Image(systemName: "plus")
                        .padding(5)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color.gray.opacity(0.06))
    }

    private func isRightMostTab(_ id: UUID) -> Bool {
        viewModel.sortedTabs.last?.id == id
    }

    private func pinnedTabSymbol(for tab: Tab) -> String {
        let trimmedTitle = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstCharacter = trimmedTitle.first {
            return String(firstCharacter).uppercased()
        }

        if let host = URL(string: tab.urlString)?.host, let firstHostCharacter = host.first {
            return String(firstHostCharacter).uppercased()
        }

        return "•"
    }

    private func faviconImage(for tab: Tab) -> NSImage? {
        guard let faviconData = tab.faviconData else { return nil }
        return NSImage(data: faviconData)
    }
}

private struct TabDropDelegate: DropDelegate {
    let targetTabID: UUID
    @Binding var draggedTabID: UUID?
    let onMove: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedTabID else { return }
        guard draggedTabID != targetTabID else { return }
        onMove(draggedTabID, targetTabID)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        return true
    }
}

private struct MiddleClickCatcher: NSViewRepresentable {
    let onMiddleClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMiddleClick: onMiddleClick)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        let recognizer = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMiddleClick))
        recognizer.buttonMask = 0x4
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator: NSObject {
        let onMiddleClick: () -> Void

        init(onMiddleClick: @escaping () -> Void) {
            self.onMiddleClick = onMiddleClick
        }

        @objc
        func handleMiddleClick() {
            onMiddleClick()
        }
    }
}
