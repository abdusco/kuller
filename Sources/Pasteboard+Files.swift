import AppKit

enum FilePasteboard {
    /// Writes the given file URLs to the general pasteboard as file
    /// references, so a subsequent Cmd+V in Finder (or any app that accepts
    /// file drops/pastes) copies the actual files.
    static func copy(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
    }
}
