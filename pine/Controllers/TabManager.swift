import Foundation
import CoreGraphics

final class TabManager {
    private static let maxSplitPanes = 4
    private struct ClosedTabState {
        let profileID: UUID
        let urlString: String
        let title: String
        let isPrivate: Bool
        let isPinned: Bool
    }

    private let store: BrowserStore
    private var closedTabsStack: [ClosedTabState] = []

    var onTabRemoved: ((UUID) -> Void)?
    var onTabLoaded: ((UUID, String) -> Void)?

    init(store: BrowserStore) {
        self.store = store
    }

    @discardableResult
    func newTab(
        urlString: String = "https://example.com",
        shouldSelect: Bool = true,
        shouldLoad: Bool = true,
        focusAddressBar: Bool = false,
        isPrivate: Bool = false,
        profileID: UUID? = nil
    ) -> UUID {
        let targetProfileID = profileID ?? store.currentProfileID
        let tab = Tab(profileID: targetProfileID, urlString: urlString, isPrivate: isPrivate)
        store.tabs.append(tab)
        store.normalizePinnedOrdering()
        if shouldSelect {
            store.setSelectedTabID(tab.id)
        }
        if shouldLoad {
            onTabLoaded?(tab.id, urlString)
        }
        if focusAddressBar {
            store.requestAddressBarFocus()
        }
        return tab.id
    }

    @discardableResult
    func newBlankTab(shouldSelect: Bool = true, isPrivate: Bool = false) -> UUID {
        newTab(urlString: "about:blank", shouldSelect: shouldSelect, shouldLoad: true, isPrivate: isPrivate, profileID: store.currentProfileID)
    }

    @discardableResult
    func newPrivateTab(urlString: String = "https://example.com", focusAddressBar: Bool = false) -> UUID {
        newTab(urlString: urlString, focusAddressBar: focusAddressBar, isPrivate: true, profileID: store.currentProfileID)
    }

    func closeTab(id: UUID) {
        guard let closedIndex = store.tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = (store.selectedTabID == id)
        let closedTab = store.tabs[closedIndex]
        pushClosedTabState(for: closedTab)

        store.tabs.removeAll { $0.id == id }
        onTabRemoved?(id)
        maintainSplitStateOnTabRemoval(closedTabID: id)

        if store.tabs.isEmpty {
            _ = newBlankTab(shouldSelect: true, isPrivate: false)
            return
        }

        if wasSelected {
            let nextIndex = min(closedIndex, store.tabs.count - 1)
            store.setSelectedTabID(store.tabs[nextIndex].id)
            return
        }

        if let selectedTabID = store.selectedTabID, store.tabs.contains(where: { $0.id == selectedTabID }) {
            return
        }
        store.setSelectedTabID(store.tabs.first?.id)
    }

    func duplicateTab(id: UUID) {
        guard let sourceIndex = store.tabs.firstIndex(where: { $0.id == id }) else { return }
        let sourceTab = store.tabs[sourceIndex]
        let duplicate = Tab(
            profileID: sourceTab.profileID,
            urlString: sourceTab.urlString,
            title: sourceTab.title,
            isPrivate: sourceTab.isPrivate,
            isPinned: sourceTab.isPinned,
            zoomFactor: sourceTab.zoomFactor,
            isReaderModeEnabled: sourceTab.isReaderModeEnabled,
            faviconData: sourceTab.faviconData
        )
        store.tabs.insert(duplicate, at: min(sourceIndex + 1, store.tabs.count))
        store.normalizePinnedOrdering()
        store.setSelectedTabID(duplicate.id)
        onTabLoaded?(duplicate.id, sourceTab.urlString)
    }

    func closeOtherTabs(keeping id: UUID) {
        guard store.tabs.contains(where: { $0.id == id }) else { return }
        let removedTabs = store.tabs.filter { $0.id != id }
        for tab in removedTabs {
            pushClosedTabState(for: tab)
            onTabRemoved?(tab.id)
        }
        store.tabs.removeAll { $0.id != id }
        store.setSelectedTabID(id)
    }

    func closeTabsToRight(of id: UUID) {
        guard let tabIndex = store.tabs.firstIndex(where: { $0.id == id }) else { return }
        guard tabIndex < store.tabs.count - 1 else { return }
        let removedTabs = Array(store.tabs[(tabIndex + 1)...])
        let removedIDs = Set(removedTabs.map(\.id))
        for tab in removedTabs {
            pushClosedTabState(for: tab)
            onTabRemoved?(tab.id)
        }
        store.tabs.removeAll { removedIDs.contains($0.id) }
        if let selectedTabID = store.selectedTabID, !store.tabs.contains(where: { $0.id == selectedTabID }) {
            store.setSelectedTabID(id)
        }
    }

    func closeTabs(inProfileID profileID: UUID) {
        let removedTabs = store.tabs.filter { $0.profileID == profileID }
        for tab in removedTabs {
            onTabRemoved?(tab.id)
        }
        let removedIDs = Set(removedTabs.map(\.id))
        store.tabs.removeAll { removedIDs.contains($0.id) }
        closedTabsStack.removeAll { $0.profileID == profileID }
    }

    func setTabPinned(id: UUID, isPinned: Bool) {
        guard let index = store.tabs.firstIndex(where: { $0.id == id }) else { return }
        store.tabs[index].isPinned = isPinned
        store.normalizePinnedOrdering()
    }

    func reorderTab(draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID else { return }
        guard let sourceIndex = store.tabs.firstIndex(where: { $0.id == draggedID }) else { return }
        guard let destinationIndex = store.tabs.firstIndex(where: { $0.id == targetID }) else { return }
        let movedTab = store.tabs.remove(at: sourceIndex)
        let adjustedDestination = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        store.tabs.insert(movedTab, at: adjustedDestination)
        store.normalizePinnedOrdering()
    }

    func beginTabDrag(tabID: UUID) {
        store.isDraggingTab = true
        store.draggedTabID = tabID
        store.currentDropTarget = nil
        store.intendedSplitSide = .none
    }

    func updateTabDropContext(targetTabID: UUID?, splitSide: SplitDropSide) {
        if store.currentDropTarget == targetTabID, store.intendedSplitSide == splitSide {
            return
        }
        store.currentDropTarget = targetTabID
        store.intendedSplitSide = splitSide
    }

    func clearTabDropContext() {
        store.isDraggingTab = false
        store.draggedTabID = nil
        store.currentDropTarget = nil
        store.intendedSplitSide = .none
    }

    func dropDraggedTabOnTab(targetTabID: UUID) {
        guard let draggedTabID = store.draggedTabID else {
            clearTabDropContext()
            return
        }
        applySplit(primaryTabID: targetTabID, secondaryTabID: draggedTabID, layout: .vertical)
        clearTabDropContext()
    }

    func dropDraggedTabOnSplitSide(targetTabID: UUID, splitSide: SplitDropSide) {
        guard let draggedTabID = store.draggedTabID else {
            clearTabDropContext()
            return
        }
        switch splitSide {
        case .left:
            applySplit(primaryTabID: draggedTabID, secondaryTabID: targetTabID, layout: .vertical)
        case .right:
            applySplit(primaryTabID: targetTabID, secondaryTabID: draggedTabID, layout: .vertical)
        case .top:
            applySplit(primaryTabID: draggedTabID, secondaryTabID: targetTabID, layout: .horizontal)
        case .bottom:
            applySplit(primaryTabID: targetTabID, secondaryTabID: draggedTabID, layout: .horizontal)
        case .none:
            applySplit(primaryTabID: targetTabID, secondaryTabID: draggedTabID, layout: .vertical)
        }
        clearTabDropContext()
    }

    func dropDraggedTabOnContent(splitSide: SplitDropSide) {
        guard let draggedTabID = store.draggedTabID else {
            clearTabDropContext()
            return
        }
        if splitSide == .none {
            if store.isSplitViewEnabled {
                appendSplitTabIfPossible(draggedTabID)
            }
            clearTabDropContext()
            return
        }
        guard let anchorTabID = contentDropAnchorTabID(excluding: draggedTabID) else {
            clearTabDropContext()
            return
        }

        switch splitSide {
        case .left:
            applySplit(primaryTabID: draggedTabID, secondaryTabID: anchorTabID, layout: .vertical)
        case .right:
            applySplit(primaryTabID: anchorTabID, secondaryTabID: draggedTabID, layout: .vertical)
        case .top:
            applySplit(primaryTabID: draggedTabID, secondaryTabID: anchorTabID, layout: .horizontal)
        case .bottom:
            applySplit(primaryTabID: anchorTabID, secondaryTabID: draggedTabID, layout: .horizontal)
        case .none:
            break
        }
        clearTabDropContext()
    }

    func selectTab(atOneBasedIndex index: Int) {
        guard index >= 1, index <= store.tabs.count else { return }
        selectTab(id: store.tabs[index - 1].id)
    }

    func cycleTab(forward: Bool) {
        guard let selectedTabID = store.selectedTabID else { return }
        guard let currentIndex = store.tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        guard !store.tabs.isEmpty else { return }
        let nextIndex = forward
            ? (currentIndex + 1) % store.tabs.count
            : (currentIndex - 1 + store.tabs.count) % store.tabs.count
        selectTab(id: store.tabs[nextIndex].id)
    }

    func selectTab(id: UUID) {
        guard store.tabs.contains(where: { $0.id == id }) else { return }
        if store.isSplitViewEnabled {
            let splitIDs = currentSplitTabIDs()
            if splitIDs.contains(id) {
                if id == store.selectedTabID {
                    store.activePane = .primary
                    return
                }

                if id == store.splitSecondaryTabID {
                    store.activePane = .secondary
                    return
                }

                if let additionalIndex = store.splitAdditionalTabIDs.firstIndex(of: id) {
                    let previousSecondaryID = store.splitSecondaryTabID
                    store.splitAdditionalTabIDs.remove(at: additionalIndex)
                    if let previousSecondaryID, previousSecondaryID != id {
                        store.splitAdditionalTabIDs.insert(previousSecondaryID, at: additionalIndex)
                    }
                    store.splitSecondaryTabID = id
                    store.activePane = .secondary
                    return
                }
            }
        }

        let previousPrimaryID = store.selectedTabID
        store.setSelectedTabID(id)
        guard store.isSplitViewEnabled else { return }
        if store.splitSecondaryTabID == id,
           let previousPrimaryID,
           previousPrimaryID != id,
           store.tabs.contains(where: { $0.id == previousPrimaryID }) {
            store.splitSecondaryTabID = previousPrimaryID
        }
    }

    func closeCurrentTab() {
        guard let selectedTabID = store.selectedTabID else { return }
        closeTab(id: selectedTabID)
    }

    func reopenClosedTab() {
        guard let closed = closedTabsStack.popLast() else { return }
        let reopenedID = newTab(
            urlString: closed.urlString,
            shouldSelect: true,
            shouldLoad: true,
            isPrivate: closed.isPrivate,
            profileID: closed.profileID
        )
        if let index = store.tabs.firstIndex(where: { $0.id == reopenedID }) {
            store.tabs[index].title = closed.title
            store.tabs[index].isPinned = closed.isPinned
            store.tabs[index].lastSelectedAt = Date()
        }
        store.normalizePinnedOrdering()
    }

    func replaceAllTabs(with newTabs: [Tab], selectedTabID: UUID?) {
        disableSplitView()
        for tab in store.tabs {
            onTabRemoved?(tab.id)
        }
        store.tabs = newTabs
        store.normalizePinnedOrdering()

        if store.tabs.isEmpty {
            _ = newBlankTab(shouldSelect: true, isPrivate: false)
            return
        }

        if let selectedTabID, store.tabs.contains(where: { $0.id == selectedTabID }) {
            store.setSelectedTabID(selectedTabID)
        } else {
            store.setSelectedTabID(store.tabs.first?.id)
        }

        for tab in store.tabs {
            onTabLoaded?(tab.id, tab.urlString)
        }
    }

    func enableSplitView(withSecondaryTabID secondaryTabID: UUID) {
        guard let primaryID = store.selectedTabID else { return }
        guard secondaryTabID != primaryID else { return }
        guard store.tabs.contains(where: { $0.id == secondaryTabID }) else { return }
        store.isSplitViewEnabled = true
        store.splitLayout = .vertical
        store.splitSecondaryTabID = secondaryTabID
        store.activePane = .primary
    }

    func disableSplitView() {
        store.isSplitViewEnabled = false
        store.splitSecondaryTabID = nil
        store.splitAdditionalTabIDs = []
        store.activePane = .primary
    }

    func setSecondaryTab(id: UUID?) {
        guard store.isSplitViewEnabled else {
            store.splitSecondaryTabID = nil
            return
        }
        guard let id else {
            store.splitSecondaryTabID = nil
            return
        }
        guard let primaryID = store.selectedTabID else { return }
        guard id != primaryID else { return }
        guard store.tabs.contains(where: { $0.id == id }) else { return }
        store.splitSecondaryTabID = id
        store.splitAdditionalTabIDs.removeAll { $0 == id }
    }

    func swapSplitPanes() {
        guard store.isSplitViewEnabled,
              let primaryID = store.selectedTabID,
              let secondaryID = store.splitSecondaryTabID,
              store.tabs.contains(where: { $0.id == primaryID }),
              store.tabs.contains(where: { $0.id == secondaryID }) else { return }
        store.setSelectedTabID(secondaryID)
        store.splitSecondaryTabID = primaryID
    }

    func setActivePane(_ pane: ActivePane) {
        guard store.isSplitViewEnabled else {
            store.activePane = .primary
            return
        }
        if pane == .secondary,
           let secondaryID = store.splitSecondaryTabID,
           store.tabs.contains(where: { $0.id == secondaryID }) {
            store.activePane = .secondary
            return
        }
        store.activePane = .primary
    }

    func switchActivePane(forward: Bool) {
        guard store.isSplitViewEnabled else {
            store.activePane = .primary
            return
        }
        let target: ActivePane = forward ? .secondary : .primary
        setActivePane(target)
    }

    func setSplitRatio(_ ratio: CGFloat) {
        store.setSplitRatio(ratio)
    }

    func resetSplitRatio() {
        store.setSplitRatio(0.5)
    }

    func toggleSplitView() {
        if store.isSplitViewEnabled {
            disableSplitView()
            return
        }
        guard let secondaryID = preferredSecondaryTabID() else {
            let newTabID = newTab(
                urlString: "https://example.com",
                shouldSelect: false,
                shouldLoad: true,
                isPrivate: false,
                profileID: store.currentProfileID
            )
            enableSplitView(withSecondaryTabID: newTabID)
            return
        }
        enableSplitView(withSecondaryTabID: secondaryID)
    }

    private func pushClosedTabState(for tab: Tab) {
        let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "New Tab" : title
        closedTabsStack.append(
            ClosedTabState(
                profileID: tab.profileID,
                urlString: tab.urlString,
                title: displayTitle,
                isPrivate: tab.isPrivate,
                isPinned: tab.isPinned
            )
        )
    }

    private func preferredSecondaryTabID() -> UUID? {
        guard let primaryID = store.selectedTabID else { return nil }
        let candidates = store.tabs.filter { $0.id != primaryID }
        guard !candidates.isEmpty else { return nil }
        return candidates
            .sorted { lhs, rhs in
                (lhs.lastSelectedAt ?? .distantPast) > (rhs.lastSelectedAt ?? .distantPast)
            }
            .first?
            .id
    }

    private func maintainSplitStateOnTabRemoval(closedTabID: UUID) {
        guard store.isSplitViewEnabled else { return }
        // Keep split mode only when two distinct tabs still exist.
        // If only one tab remains, exiting split is less surprising than auto-creating tabs.
        guard store.tabs.count >= 2 else {
            disableSplitView()
            return
        }

        store.splitAdditionalTabIDs.removeAll { $0 == closedTabID }

        if store.splitSecondaryTabID == closedTabID {
            if let firstAdditional = store.splitAdditionalTabIDs.first {
                store.splitSecondaryTabID = firstAdditional
                store.splitAdditionalTabIDs.removeFirst()
            } else {
                store.splitSecondaryTabID = preferredSecondaryTabID()
            }
            if store.splitSecondaryTabID == nil {
                disableSplitView()
            }
            if store.activePane == .secondary {
                store.activePane = .primary
            }
            return
        }

        if let selectedPrimaryID = store.selectedTabID,
           store.splitSecondaryTabID == selectedPrimaryID {
            store.splitSecondaryTabID = preferredSecondaryTabID()
            if store.splitSecondaryTabID == nil {
                disableSplitView()
            }
        }
    }

    private func applySplit(primaryTabID: UUID, secondaryTabID: UUID, layout: SplitLayout) {
        guard primaryTabID != secondaryTabID else { return }
        guard store.tabs.contains(where: { $0.id == primaryTabID }) else { return }
        guard store.tabs.contains(where: { $0.id == secondaryTabID }) else { return }

        if store.isSplitViewEnabled {
            let splitIDs = currentSplitTabIDs()
            if splitIDs.contains(primaryTabID) {
                if !splitIDs.contains(secondaryTabID) {
                    appendSplitTabIfPossible(secondaryTabID)
                } else {
                    store.splitSecondaryTabID = secondaryTabID
                    store.splitAdditionalTabIDs.removeAll { $0 == secondaryTabID }
                }
                store.setSelectedTabID(primaryTabID)
                store.isSplitViewEnabled = true
                store.splitLayout = layout
                store.activePane = .primary
                return
            }
        }

        store.setSelectedTabID(primaryTabID)
        store.isSplitViewEnabled = true
        store.splitLayout = layout
        store.splitSecondaryTabID = secondaryTabID
        store.splitAdditionalTabIDs = []
        store.activePane = .primary
    }

    private func appendSplitTabIfPossible(_ tabID: UUID) {
        guard tabID != store.selectedTabID else { return }
        guard store.tabs.contains(where: { $0.id == tabID }) else { return }
        let existingIDs = currentSplitTabIDs()
        guard !existingIDs.contains(tabID) else { return }
        guard existingIDs.count < Self.maxSplitPanes else { return }

        if store.splitSecondaryTabID == nil {
            store.splitSecondaryTabID = tabID
            return
        }
        store.splitAdditionalTabIDs.append(tabID)
    }

    private func currentSplitTabIDs() -> [UUID] {
        var ids: [UUID] = []
        if let primaryID = store.selectedTabID {
            ids.append(primaryID)
        }
        if let secondaryID = store.splitSecondaryTabID, !ids.contains(secondaryID) {
            ids.append(secondaryID)
        }
        for id in store.splitAdditionalTabIDs where !ids.contains(id) {
            ids.append(id)
        }
        return ids
    }

    private func contentDropAnchorTabID(excluding draggedTabID: UUID) -> UUID? {
        if let selectedTabID = store.selectedTabID,
           selectedTabID != draggedTabID,
           store.tabs.contains(where: { $0.id == selectedTabID }) {
            return selectedTabID
        }

        if store.isSplitViewEnabled,
           let secondaryTabID = store.splitSecondaryTabID,
           secondaryTabID != draggedTabID,
           store.tabs.contains(where: { $0.id == secondaryTabID }) {
            return secondaryTabID
        }

        return store.tabs.first(where: { $0.id != draggedTabID })?.id
    }
}
