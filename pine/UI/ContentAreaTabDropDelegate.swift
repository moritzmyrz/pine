import SwiftUI
import UniformTypeIdentifiers

struct ContentAreaTabDropDelegate: DropDelegate {
    let hoverController: TabSnapHoverController
    let contentWidth: CGFloat
    let onHoverSideChanged: (SplitDropSide) -> Void
    let onDropWithSide: (SplitDropSide) -> Void
    let onDropExit: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        onHoverSideChanged(hoverController.splitSide(for: info.location, in: CGSize(width: contentWidth, height: contentWidth)))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onHoverSideChanged(hoverController.splitSide(for: info.location, in: CGSize(width: contentWidth, height: contentWidth)))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onDropExit()
    }

    func performDrop(info: DropInfo) -> Bool {
        let side = hoverController.splitSide(for: info.location, in: CGSize(width: contentWidth, height: contentWidth))
        onDropWithSide(side)
        return true
    }
}
