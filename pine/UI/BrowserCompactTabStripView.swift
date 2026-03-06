import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BrowserCompactTabStripView: View {
    @ObservedObject var viewModel: BrowserViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.sortedTabs) { tab in
                    tabItem(for: tab)
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
            .onDrop(of: [UTType.text], delegate: StripDropDelegate(viewModel: viewModel))
        }
        .background(Color.gray.opacity(0.06))
    }

    private func tabItem(for tab: Tab) -> some View {
        tabLabel(for: tab)
            .padding(.horizontal, tab.isPinned ? 8 : 10)
            .padding(.vertical, 5)
            .background(tab.id == viewModel.activeTab?.id ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                TabDropOverlayView(
                    showOverlay: shouldShowDropOverlay(for: tab.id),
                    isTarget: viewModel.store.currentDropTarget == tab.id,
                    highlightLeft: isLeftSplitTarget(for: tab.id),
                    highlightRight: isRightSplitTarget(for: tab.id)
                )
            }
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
                viewModel.beginTabDrag(tabID: tab.id)
                return NSItemProvider(object: tab.id.uuidString as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: TabDropDelegate(viewModel: viewModel, targetTabID: tab.id)
            )
    }

    @ViewBuilder
    private func tabLabel(for tab: Tab) -> some View {
        HStack(spacing: 6) {
            if tab.isPinned {
                pinnedTabIcon(for: tab)
            } else {
                regularTabLeading(for: tab)
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
    }

    @ViewBuilder
    private func pinnedTabIcon(for tab: Tab) -> some View {
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
    }

    @ViewBuilder
    private func regularTabLeading(for tab: Tab) -> some View {
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

    private func shouldShowDropOverlay(for tabID: UUID) -> Bool {
        viewModel.store.isDraggingTab && viewModel.store.draggedTabID != tabID
    }

    private func isLeftSplitTarget(for tabID: UUID) -> Bool {
        viewModel.store.currentDropTarget == tabID && viewModel.store.intendedSplitSide == .left
    }

    private func isRightSplitTarget(for tabID: UUID) -> Bool {
        viewModel.store.currentDropTarget == tabID && viewModel.store.intendedSplitSide == .right
    }
}

private struct TabDropDelegate: DropDelegate {
    let viewModel: BrowserViewModel
    let targetTabID: UUID

    func dropEntered(info: DropInfo) {
        updateDropIntent(from: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropIntent(from: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if viewModel.store.currentDropTarget == targetTabID {
            viewModel.updateTabDropContext(targetTabID: nil, splitSide: .none)
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        let splitSide = resolvedSplitSide(from: info)
        if splitSide == .none {
            viewModel.dropDraggedTabOnTab(targetTabID: targetTabID)
        } else {
            viewModel.dropDraggedTabOnSplitSide(targetTabID: targetTabID, splitSide: splitSide)
        }
        return true
    }

    private func updateDropIntent(from info: DropInfo) {
        guard viewModel.store.draggedTabID != targetTabID else {
            viewModel.updateTabDropContext(targetTabID: nil, splitSide: .none)
            return
        }
        viewModel.updateTabDropContext(targetTabID: targetTabID, splitSide: resolvedSplitSide(from: info))
    }

    private func resolvedSplitSide(from info: DropInfo) -> SplitDropSide {
        let x = info.location.x
        if x <= 28 {
            return .left
        }
        if x >= 56 {
            return .right
        }
        return .none
    }
}

private struct StripDropDelegate: DropDelegate {
    let viewModel: BrowserViewModel

    func performDrop(info: DropInfo) -> Bool {
        viewModel.clearTabDropContext()
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
