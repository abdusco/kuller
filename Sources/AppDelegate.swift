import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Borderless windows can't become key/main by default, which would silently
/// swallow all keyboard input (p/x/j/k/arrows/Cmd+Enter/etc). Override to
/// keep keyboard handling working with no title bar.
final class BorderlessKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
