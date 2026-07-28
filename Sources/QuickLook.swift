import AppKit
import Quartz

/// Drives the shared Quick Look panel — the same one Finder uses, so Space
/// previews behave the way they do there (including arrow-key navigation
/// through the whole selection).
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private var urls: [URL] = []

    /// Space toggles: opens the panel for `urls`, or closes it if it's
    /// already up.
    func toggle(urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        guard !urls.isEmpty else { return }
        self.urls = urls
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func close() {
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    var isVisible: Bool {
        QLPreviewPanel.shared()?.isVisible ?? false
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard urls.indices.contains(index) else { return nil }
        return urls[index] as NSURL
    }
}
