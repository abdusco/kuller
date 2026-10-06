import AppKit

/// Finder launches have no path arguments. Let the user choose the same
/// files and folders accepted by the CLI, with visible errors and retries.
func chooseLaunchImages() -> [ImageItem]? {
    let panel = NSOpenPanel()
    panel.title = "Choose Images to Cull"
    panel.prompt = "Cull"
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    NSApp.activate(ignoringOtherApps: true)
    while panel.runModal() == .OK {
        do {
            let images = try ImageDiscovery.resolveImages(fromArguments: panel.urls.map(\.path))
            if !images.isEmpty { return images }
            throw CLIError.message("No supported images were found in the selection.")
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t Open Images"
            alert.informativeText = String(describing: error)
            alert.runModal()
        }
    }
    return nil
}
