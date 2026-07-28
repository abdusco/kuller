import AppKit

/// Thin wrapper around a local NSEvent key-down monitor, scoped to this
/// process's own events (no accessibility permission needed). SwiftUI's
/// `.onKeyPress`/`.keyboardShortcut` modifiers are workable but flaky for
/// letter keys without modifiers plus separate Cmd-combos in the same view,
/// so views install/remove one of these in onAppear/onDisappear instead.
final class KeyMonitor {
    private var monitor: Any?
    private let handler: (NSEvent) -> Bool

    /// `handler` returns true if it consumed the event (stops propagation).
    init(handler: @escaping (NSEvent) -> Bool) {
        self.handler = handler
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.handler(event) {
                return nil
            }
            return event
        }
    }

    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        stop()
    }
}
