import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var items: [ImageItem]
    @Published var decisions: [UUID: Decision] = [:]
    @Published var currentIndex: Int = 0
    @Published var phase: AppPhase = .culling
    @Published var isCropping: Bool = false
    @Published var cropRects: [UUID: NormalizedRect] = [:]
    @Published var cullingImageSize: CGSize?
    @Published var cullingImageOffset: CGSize = .zero

    init(items: [ImageItem]) {
        self.items = items
    }

    var currentItem: ImageItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var picks: [ImageItem] {
        items.filter { decisions[$0.id] == .pick }
    }

    /// Rejects for the review screen: explicit rejects plus (once decisions
    /// cover every item on submit) anything left undecided.
    var rejects: [ImageItem] {
        items.filter { decisions[$0.id] != .pick }
    }

    func decide(_ item: ImageItem, _ decision: Decision) {
        // Only finishing an undecided original auto-advances to review.
        // Picking/rejecting a new crop should leave the user in culling,
        // even if it was the only undecided item after returning from review.
        let wasUndecided = decisions[item.id] == nil
        decisions[item.id] = decision
        advance()
        if wasUndecided, !item.isVirtualCopy, decisions.count == items.count {
            phase = .review
        }
    }

    func advance() {
        guard currentIndex < items.count - 1 else { return }
        currentIndex += 1
    }

    func goToPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    func goToNext() {
        advance()
    }

    func jumpTo(_ item: ImageItem) {
        guard let index = items.firstIndex(of: item) else { return }
        currentIndex = index
    }

    /// Submits early (e.g. Cmd+Return): any image without an explicit decision
    /// becomes a reject.
    func submit() {
        for item in items where decisions[item.id] == nil {
            decisions[item.id] = .reject
        }
        phase = .review
    }

    func returnToCulling() {
        phase = .culling
    }

    /// Reclassifies items (e.g. dragged from one review column onto the
    /// other) to the given decision.
    func setDecision(ids: [UUID], to decision: Decision) {
        for id in ids {
            decisions[id] = decision
        }
    }

    /// Commits a crop as a new, independent item (same `url`, fresh `id`)
    /// inserted directly after `original` — rather than cropping `original`
    /// itself — so the source file stays untouched and browsable. Inserting
    /// right after `original`'s current index never shifts `original`'s own
    /// index, so `currentIndex`/`currentItem` don't need adjusting.
    @discardableResult
    func insertVirtualCopy(of original: ImageItem, cropRect: NormalizedRect) -> ImageItem {
        let existingCopies = items.filter { $0.url == original.url && $0.isVirtualCopy }.count
        let copy = ImageItem(url: original.url, isVirtualCopy: true, copyIndex: existingCopies + 1)
        let insertAt = (items.firstIndex(of: original) ?? items.count - 1) + 1
        items.insert(copy, at: insertAt)
        cropRects[copy.id] = cropRect
        return copy
    }

    /// Removes a virtual copy created by `insertVirtualCopy`, along with its
    /// decision/crop state. Adjusts `currentIndex` so the item the user was
    /// actually looking at (by identity, not raw index) stays current.
    func removeVirtualCopy(_ item: ImageItem) {
        guard item.isVirtualCopy, let index = items.firstIndex(of: item) else { return }
        items.remove(at: index)
        decisions[item.id] = nil
        cropRects[item.id] = nil
        CroppedImageRenderer.invalidate(itemID: item.id)
        if currentIndex > index {
            currentIndex -= 1
        } else if currentIndex >= items.count {
            currentIndex = max(0, items.count - 1)
        }
    }
}
