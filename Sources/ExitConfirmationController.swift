import AppKit

/// Presents one non-blocking exit confirmation at a time. Keeping the alert
/// asynchronous leaves AppKit's normal event loop and layout cycle running.
final class ExitConfirmationController {
    static let shared = ExitConfirmationController()

    private(set) var isPresenting = false

    private init() {}

    func requestExit(appState: AppState, parentWindow: NSWindow?) {
        guard !isPresenting else { return }

        guard let alert = confirmationAlert(for: appState) else {
            NSApp.terminate(nil)
            return
        }

        guard let parentWindow else { return }

        isPresenting = true
        alert.beginSheetModal(for: parentWindow) { [weak self] response in
            self?.isPresenting = false
            if response == .alertFirstButtonReturn {
                NSApp.terminate(nil)
            }
        }
    }

    private func confirmationAlert(for appState: AppState) -> NSAlert? {
        let alert = NSAlert()
        alert.alertStyle = .warning

        switch appState.phase {
        case .culling:
            guard !appState.decisions.isEmpty else { return nil }
            let pendingCount = appState.items.count - appState.decisions.count
            guard pendingCount > 0 else { return nil }
            alert.messageText = "Quit with \(pendingCount) image\(pendingCount == 1 ? "" : "s") left to review?"
            alert.informativeText = "Images you haven't picked or rejected yet will be left undecided."
        case .review:
            let pickCount = appState.picks.count
            let rejectCount = appState.rejects.count
            alert.messageText = "Quit and discard this sort?"
            alert.informativeText = "\(pickCount) pick\(pickCount == 1 ? "" : "s"), \(rejectCount) reject\(rejectCount == 1 ? "" : "s")."
        }

        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        // Escape cancels instead of confirming the destructive first button.
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        return alert
    }
}
