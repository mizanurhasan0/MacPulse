import AppKit
import SwiftUI

/// Tracks AppKit mouse events in screen coordinates, which stay stable as the
/// window moves. Moving the panel never feeds back into the pointer delta.
struct CompanionDragHandle: NSViewRepresentable {
    let label: String
    let help: String
    var onClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: HandleView, context: Context) {
        view.onClick = onClick
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(onClick == nil ? .group : .button)
        view.setAccessibilityLabel(label)
        view.setAccessibilityHelp(help)
        view.toolTip = help
    }

    final class HandleView: NSView {
        var onClick: (() -> Void)?
        private var pressPoint: NSPoint?
        private var windowOrigin: NSPoint?
        private var hasDragged = false
        private let dragThreshold: CGFloat = 3

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            pressPoint = NSEvent.mouseLocation
            windowOrigin = window?.frame.origin
            hasDragged = false
        }

        override func mouseDragged(with event: NSEvent) {
            updateDrag()
        }

        override func mouseUp(with event: NSEvent) {
            guard pressPoint != nil else { return }
            if hasDragged { updateDrag() }
            let wasDragging = hasDragged
            pressPoint = nil
            windowOrigin = nil
            hasDragged = false
            if wasDragging {
                if let window, !window.frameAutosaveName.isEmpty {
                    window.saveFrame(usingName: window.frameAutosaveName)
                }
                return
            }
            let point = convert(event.locationInWindow, from: nil)
            if bounds.contains(point) { onClick?() }
        }

        private func updateDrag() {
            guard let pressPoint, let windowOrigin, let window else { return }
            let pointer = NSEvent.mouseLocation
            let dx = pointer.x - pressPoint.x
            let dy = pointer.y - pressPoint.y
            guard hasDragged || hypot(dx, dy) >= dragThreshold else { return }
            hasDragged = true
            window.setFrameOrigin(NSPoint(x: windowOrigin.x + dx, y: windowOrigin.y + dy))
        }

        override func accessibilityPerformPress() -> Bool {
            guard let onClick else { return false }
            onClick()
            return true
        }
    }
}
