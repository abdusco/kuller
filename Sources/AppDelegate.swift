import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
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
        confirmExitIfNeeded(appState: appState)
    }
}
