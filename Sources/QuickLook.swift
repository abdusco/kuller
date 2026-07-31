import AppKit
import Quartz

/// Drives the shared Quick Look panel — the same one Finder uses, so Space
/// previews behave the way they do there (including arrow-key navigation
/// through the whole selection).
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private var urls: [URL] = []

    /// Space toggles: opens the panel showing `items` (resolved to their
    /// committed crop, if any — see CroppedImageRenderer) starting at
    /// `startIndex`, or closes it if it's already up. Passing more than one
    /// item is what makes the panel's arrow-key navigation work.
    func toggle(items: [ImageItem], cropRects: [UUID: NormalizedRect], startIndex: Int = 0) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        guard !items.isEmpty else { return }
        resolveURLs(for: items, cropRects: cropRects) { [weak self] resolved in
            guard let self else { return }
            self.urls = resolved
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
            // Must come after reloadData, or the panel has no items to index into.
            if resolved.indices.contains(startIndex) {
                panel.currentPreviewItemIndex = startIndex
            }
        }
    }

    private func resolveURLs(for items: [ImageItem], cropRects: [UUID: NormalizedRect], completion: @escaping ([URL]) -> Void) {
        var resolved = [URL?](repeating: nil, count: items.count)
        let group = DispatchGroup()
        for (index, item) in items.enumerated() {
            group.enter()
            CroppedImageRenderer.resolvedURL(for: item, cropRects: cropRects) { url in
                resolved[index] = url
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(resolved.compactMap { $0 })
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
