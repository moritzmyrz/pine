import AppKit
import SwiftUI

struct ContentAreaDragDestinationView: NSViewRepresentable {
    let onDragMove: (CGPoint) -> Void
    let onDragExit: () -> Void
    let onDrop: (CGPoint) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onDragMove: onDragMove, onDragExit: onDragExit, onDrop: onDrop)
    }

    func makeNSView(context: Context) -> DragDestinationNSView {
        let view = DragDestinationNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DragDestinationNSView, context: Context) {
        nsView.coordinator = context.coordinator
    }
}

final class DragDestinationNSView: NSView {
    weak var coordinator: ContentAreaDragDestinationView.Coordinator?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.string])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let locationInView = convert(sender.draggingLocation, from: nil)
        coordinator?.onDragMove(locationInView)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        coordinator?.onDragExit()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let locationInView = convert(sender.draggingLocation, from: nil)
        return coordinator?.onDrop(locationInView) ?? false
    }
}

extension ContentAreaDragDestinationView {
    final class Coordinator {
        let onDragMove: (CGPoint) -> Void
        let onDragExit: () -> Void
        let onDrop: (CGPoint) -> Bool

        init(
            onDragMove: @escaping (CGPoint) -> Void,
            onDragExit: @escaping () -> Void,
            onDrop: @escaping (CGPoint) -> Bool
        ) {
            self.onDragMove = onDragMove
            self.onDragExit = onDragExit
            self.onDrop = onDrop
        }
    }
}
