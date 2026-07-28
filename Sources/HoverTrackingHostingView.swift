import AppKit
import SwiftUI
import Quartz

/// The canvas window's hosting view, handling window-level interaction at the
/// AppKit layer rather than via SwiftUI gestures:
///
/// - hover, to fade the title bar in/out
/// - drag, forwarded to `NSWindow.performDrag` so the window moves under
///   AppKit's own native drag loop
/// - pinch, via `magnify(with:)`'s incremental deltas, to resize the window
///
/// Doing these in SwiftUI instead is what made moving/resizing glitch: a
/// DragGesture reports translations in the view's coordinate space, which
/// itself moves as the window moves, so each frame's offset feeds back into
/// the next one.
final class HoverTrackingHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: (Bool) -> Void = { _ in }
    var onMagnify: (CGFloat) -> Void = { _ in }
    var onResetSize: () -> Void = {}
    /// Gates window drag/resize so it only applies while culling — the
    /// review screen needs normal mouse handling for marquee selection and
    /// dragging items out to Finder.
    var allowsWindowInteraction: () -> Bool = { true }

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange(false)
    }

    override func mouseDown(with event: NSEvent) {
        guard allowsWindowInteraction() else {
            super.mouseDown(with: event)
            return
        }
        if event.clickCount == 2 {
            onResetSize()
            return
        }
        // Hands off to AppKit's native window-drag loop: smooth, and immune
        // to the coordinate-space feedback that plagued the SwiftUI version.
        window?.performDrag(with: event)
    }

    override func magnify(with event: NSEvent) {
        guard allowsWindowInteraction() else {
            super.magnify(with: event)
            return
        }
        onMagnify(event.magnification)
    }

    // MARK: Quick Look
    //
    // QLPreviewPanel walks the responder chain looking for something willing
    // to control it; without these it opens empty.

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = QuickLookController.shared
        panel.delegate = QuickLookController.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
