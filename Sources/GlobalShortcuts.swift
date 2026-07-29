import AppKit

/// Shortcuts available from any screen: hard quit, and "exit" (Esc / Cmd+W)
/// which asks for confirmation if there are still undecided images.
/// Returns true if the event was handled.
func handleGlobalShortcuts(_ event: NSEvent, appState: AppState) -> Bool {
    let modifiers = event.modifierFlags
    let characters = event.charactersIgnoringModifiers?.lowercased()
    let escapeKeyCode: UInt16 = 53

    if modifiers.contains(.command), characters == "q" {
        NSApp.terminate(nil)
        return true
    }

    let isCmdW = modifiers.contains(.command) && characters == "w"
    let isEscape = event.keyCode == escapeKeyCode
    if isCmdW || isEscape {
        if confirmExitIfNeeded(appState: appState) {
            NSApp.terminate(nil)
        }
        return true
    }

    return false
}

/// Returns true if it's fine to proceed with exiting/closing now — either
/// there's nothing to lose, or the user confirmed discarding it via the alert.
/// Shared by the Esc/Cmd+W shortcut and the canvas window's own close-button
/// handling, so both paths behave the same way.
func confirmExitIfNeeded(appState: AppState) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning

    switch appState.phase {
    case .culling:
        let pendingCount = appState.items.count - appState.decisions.count
        guard pendingCount > 0 else { return true }
        alert.messageText = "Quit with \(pendingCount) image\(pendingCount == 1 ? "" : "s") left to review?"
        alert.informativeText = "Images you haven't picked or rejected yet will be left undecided."
    case .review:
        // Every image is decided here, so the old pending-count test never
        // fired and Esc quit outright — throwing away the whole sort, which
        // only exists in memory until the files are copied somewhere.
        let pickCount = appState.picks.count
        let rejectCount = appState.rejects.count
        alert.messageText = "Quit and discard this sort?"
        alert.informativeText = "\(pickCount) pick\(pickCount == 1 ? "" : "s"), \(rejectCount) reject\(rejectCount == 1 ? "" : "s")."
    }

    alert.addButton(withTitle: "Quit")
    alert.addButton(withTitle: "Cancel")
    // Esc should cancel the alert rather than confirm the quit it's asking
    // about; without this the second button isn't wired to Esc.
    alert.buttons.last?.keyEquivalent = "\u{1b}"
    return alert.runModal() == .alertFirstButtonReturn
}
