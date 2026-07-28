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
        requestExit(appState: appState)
        return true
    }

    return false
}

private func requestExit(appState: AppState) {
    let pendingCount = appState.items.count - appState.decisions.count
    guard pendingCount > 0, appState.phase == .culling else {
        NSApp.terminate(nil)
        return
    }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Quit with \(pendingCount) image\(pendingCount == 1 ? "" : "s") left to review?"
    alert.informativeText = "Images you haven't picked or rejected yet will be left undecided."
    alert.addButton(withTitle: "Quit")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
        NSApp.terminate(nil)
    }
}
