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
/// nothing is pending, or the user confirmed discarding pending images via
/// the alert. Shared by the Esc/Cmd+W shortcut and the canvas window's own
/// close-button handling, so both paths behave the same way.
func confirmExitIfNeeded(appState: AppState) -> Bool {
    let pendingCount = appState.items.count - appState.decisions.count
    guard pendingCount > 0, appState.phase == .culling else {
        return true
    }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Quit with \(pendingCount) image\(pendingCount == 1 ? "" : "s") left to review?"
    alert.informativeText = "Images you haven't picked or rejected yet will be left undecided."
    alert.addButton(withTitle: "Quit")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
}
