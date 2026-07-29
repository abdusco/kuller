import AppKit
import Quartz

/// Drives the shared Quick Look panel — the same one Finder uses, so Space
/// previews behave the way they do there (including arrow-key navigation
/// through the whole selection).
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private var urls: [URL] = []

    /// Space toggles: opens the panel showing `urls` starting at
    /// `startIndex`, or closes it if it's already up. Passing more than one
    /// URL is what makes the panel's arrow-key navigation work.
    func toggle(urls: [URL], startIndex: Int = 0) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        guard !urls.isEmpty else { return }
        self.urls = urls
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
        // Must come after reloadData, or the panel has no items to index into.
        if urls.indices.contains(startIndex) {
            panel.currentPreviewItemIndex = startIndex
        }
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
