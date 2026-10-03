import AppKit
import SwiftUI

@main
enum ReviewViewTests {
    static func main() {
        _ = NSApplication.shared
        let items = (0..<4).map {
            ImageItem(url: URL(fileURLWithPath: "/tmp/kuller-review-test-\($0).png"))
        }
        let state = AppState(items: items)
        state.setDecision(ids: Array(items.prefix(2)).map(\.id), to: .pick)
        state.submit()

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: ReviewView(appState: state))
        hosting.sizingOptions = []
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let grids = collectionViews(in: hosting).sorted { $0.convert(.zero, to: hosting).x < $1.convert(.zero, to: hosting).x }
        precondition(grids.count == 2, "Missing review grids")

        for index in [0, 1, 0] {
            let grid = grids[index]
            grids.forEach { $0.deselectAll(nil) }
            precondition(grid.bounds.height >= grid.enclosingScrollView!.contentView.bounds.height,
                         "Blank pane space must belong to the grid")

            // A blank-space click must activate the pane without selecting a thumbnail.
            let point = grid.convert(NSPoint(x: 10, y: grid.bounds.midY), to: nil)
            let mouseUp = NSEvent.mouseEvent(with: .leftMouseUp, location: point,
                                            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                            context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
            NSApp.postEvent(mouseUp, atStart: true)
            let mouseDown = NSEvent.mouseEvent(with: .leftMouseDown, location: point,
                                              modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            grid.mouseDown(with: mouseDown)
            precondition(grid.selectionIndexPaths.isEmpty, "Blank click selected an image")

            let selectAll = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                            modifierFlags: [.command], timestamp: 0, windowNumber: window.windowNumber,
                                            context: nil, characters: "a", charactersIgnoringModifiers: "a",
                                            isARepeat: false, keyCode: 0)!
            NSApp.sendEvent(selectAll)
            precondition(grid.selectionIndexPaths.count == 2, "Cmd+A did not select the clicked pane")
            precondition(grids[1 - index].selectionIndexPaths.isEmpty, "Cmd+A selected the other pane")
        }
        print("Passed blank-space selection and switching between review panes")
    }

    private static func collectionViews(in view: NSView) -> [ReviewCollectionView] {
        if let grid = view as? ReviewCollectionView { return [grid] }
        return view.subviews.flatMap { collectionViews(in: $0) }
    }
}
