import AppKit

/// Shortcuts available from any screen: hard quit, and "exit" (Esc / Cmd+W)
/// which asks for confirmation if there are still undecided images.
/// Returns true if the event was handled.
func handleGlobalShortcuts(_ event: NSEvent, appState: AppState) -> Bool {
    // The confirmation sheet owns Escape. Consume repeated exit shortcuts
    // while it is open so they cannot stack additional alerts behind it.
    if ExitConfirmationController.shared.isPresenting {
        return true
    }

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
        let parentWindow = NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: \.isVisible)
        ExitConfirmationController.shared.requestExit(appState: appState, parentWindow: parentWindow)
        return true
    }

    return false
}
