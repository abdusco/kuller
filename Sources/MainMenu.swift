import AppKit

/// A binary built straight with swiftc (no app bundle) starts with no main
/// menu at all, which breaks the standard app-level behaviors macOS expects:
/// Hide/Hide Others, and reliable activation/deactivation handling. Install a
/// minimal one.
func installMainMenu(appName: String = "kuller") {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(SettingsWindowController.openSettings(_:)), keyEquivalent: ",")
    settings.target = SettingsWindowController.shared
    appMenu.addItem(.separator())
    appMenu.addItem(
        withTitle: "Hide \(appName)",
        action: #selector(NSApplication.hide(_:)),
        keyEquivalent: "h"
    )
    let hideOthers = appMenu.addItem(
        withTitle: "Hide Others",
        action: #selector(NSApplication.hideOtherApplications(_:)),
        keyEquivalent: "h"
    )
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(
        withTitle: "Show All",
        action: #selector(NSApplication.unhideAllApplications(_:)),
        keyEquivalent: ""
    )
    appMenu.addItem(.separator())
    appMenu.addItem(
        withTitle: "Quit \(appName)",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )
    appMenuItem.submenu = appMenu

    // Edit menu, so Copy/Select All exist as real menu commands too. The
    // review screen's own key monitor sees these shortcuts first and
    // consumes them, so they don't fire twice.
    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editMenuItem.submenu = editMenu

    let windowMenuItem = NSMenuItem()
    mainMenu.addItem(windowMenuItem)
    let windowMenu = NSMenu(title: "Window")
    let closeWindow = windowMenu.addItem(withTitle: "Close Window", action: #selector(AppDelegate.closeWindow(_:)), keyEquivalent: "w")
    closeWindow.target = NSApp.delegate
    windowMenuItem.submenu = windowMenu

    NSApp.mainMenu = mainMenu
}
