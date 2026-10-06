import Foundation

@main
enum AppStateTests {
    static func main() {
        let cases: [(String, Bool, Bool, Decision, AppPhase)] = [
            ("pick crop after returning from review", true, true, .pick, .culling),
            ("reject crop after returning from review", true, true, .reject, .culling),
            ("pick crop while original is undecided", false, true, .pick, .culling),
            ("reject crop while original is undecided", false, true, .reject, .culling),
            ("pick last original", false, false, .pick, .review),
            ("reject last original", false, false, .reject, .review),
            ("redecide original after returning from review", true, false, .pick, .culling),
        ]
        for (name, returnFromReview, decideCrop, decision, expectedPhase) in cases {
            let original = ImageItem(url: URL(fileURLWithPath: "/tmp/kuller-state-test.png"))
            let state = AppState(items: [original])
            if returnFromReview {
                state.submit()
                state.returnToCulling()
            }
            let item: ImageItem
            if decideCrop {
                item = state.insertVirtualCopy(of: original,
                    cropRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5))
                state.jumpTo(item)
            } else {
                item = original
            }
            state.decide(item, decision)
            precondition(state.phase == expectedPhase, "\(name): unexpected phase")
            precondition(state.decisions[item.id] == decision, "\(name): decision was not saved")
            if decideCrop {
                precondition(state.decisions[original.id] == (returnFromReview ? .reject : nil),
                             "\(name): original decision changed")
                state.submit()
                precondition(state.phase == .review, "\(name): explicit finish did not open review")
            }
        }

        let originals = (0..<2).map { ImageItem(url: URL(fileURLWithPath: "/tmp/kuller-state-\($0).png")) }
        let state = AppState(items: originals)
        let crop = state.insertVirtualCopy(of: originals[0],
            cropRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5))
        state.jumpTo(crop)
        state.decide(crop, .pick)
        precondition(state.phase == .culling && state.currentItem == originals[1],
                     "Picking a crop did not advance to the next image in culling")
        state.decide(originals[1], .reject)
        precondition(state.phase == .culling, "An undecided original was skipped")
        state.jumpTo(originals[0])
        state.decide(originals[0], .reject)
        precondition(state.phase == .review, "Finishing originals did not auto-advance to review")
        print("Passed \(cases.count + 1) culling decision and crop transition cases")
    }
}
