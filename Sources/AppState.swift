import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var items: [ImageItem]
    @Published var decisions: [UUID: Decision] = [:]
    @Published var currentIndex: Int = 0
    @Published var phase: AppPhase = .culling

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
        // Only auto-advance to review when this decision resolved the last
        // still-undecided image. Testing decisions.count alone would bounce
        // straight back to review after returning to culling from it, since
        // submitting assigns a decision to every image.
        let wasUndecided = decisions[item.id] == nil
        decisions[item.id] = decision
        advance()
        if wasUndecided, decisions.count == items.count {
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
}
