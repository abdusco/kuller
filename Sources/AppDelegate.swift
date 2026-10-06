import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    @objc func closeWindow(_ sender: Any?) {
        NSApp.keyWindow?.performClose(sender)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Routes the canvas window's red close button through the same
/// pending-images confirmation as Esc/Cmd+W, instead of just closing.
final class CanvasWindowDelegate: NSObject, NSWindowDelegate {
    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        ExitConfirmationController.shared.requestExit(appState: appState, parentWindow: sender)
        // Exit is continued from the sheet's completion handler, never by
        // closing synchronously while AppKit is handling the close request.
        return false
    }

    /// Hard floor for the review window, enforced here rather than only via
    /// NSWindow.minSize: whatever ignores minSize for this window (hosting
    /// view sizing, the aspect-ratio/resizeIncrements interaction) cannot
    /// bypass the delegate, which AppKit consults on every user-driven
    /// resize. Culling is left alone so images stay freely scalable.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard appState.phase == .review else { return frameSize }
        return NSSize(
            width: max(frameSize.width, reviewMinWindowSize.width),
            height: max(frameSize.height, reviewMinWindowSize.height)
        )
    }
}
