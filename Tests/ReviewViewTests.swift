import AppKit
import SwiftUI

@main
enum ReviewViewTests {
    static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuller-review-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let data = bitmap.representation(using: .png, properties: [:])!
        for index in 0..<2 {
            try data.write(to: directory.appendingPathComponent("image-\(index).png"))
        }
        let items = (0..<4).map {
            ImageItem(url: directory.appendingPathComponent("image-\($0 / 2).png"),
                      isVirtualCopy: $0 % 2 == 1, copyIndex: $0 % 2)
        }
        let state = AppState(items: items)
        for item in items where item.isVirtualCopy {
            state.cropRects[item.id] = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        }
        let cropsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("kuller-crops")
        defer {
            for item in items where item.isVirtualCopy {
                try? FileManager.default.removeItem(at: cropsDirectory.appendingPathComponent(item.id.uuidString))
            }
        }
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

        var preparedDates: [UUID: Date] = [:]
        let clipboardVersion = NSPasteboard.general.changeCount
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

            // Selection alone must prepare the crop, before any copy or preview.
            let crop = items[index * 2 + 1]
            let cropURL = cropsDirectory.appendingPathComponent(crop.id.uuidString)
                .appendingPathComponent(crop.displayName)
            let deadline = Date().addingTimeInterval(5)
            while ThumbnailCache.quickPixelSize(of: cropURL) != CGSize(width: 16, height: 8), Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            precondition(ThumbnailCache.quickPixelSize(of: cropURL) == CGSize(width: 16, height: 8),
                         "Selecting the crop did not prepare it")
            // Drain queued preparation and check that reselecting reused it.
            precondition(CroppedImageRenderer.resolvedURLSync(for: crop, cropRects: state.cropRects) == cropURL)
            let modified = try cropURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
            if let previous = preparedDates[crop.id] {
                precondition(modified == previous, "Reselecting rendered the crop again")
            }
            preparedDates[crop.id] = modified
            precondition(NSPasteboard.general.changeCount == clipboardVersion, "Selection changed the clipboard")
            if index == 0, preparedDates.count == 1 {
                let unselected = items[3]
                precondition(!FileManager.default.fileExists(atPath: cropsDirectory
                    .appendingPathComponent(unselected.id.uuidString).path), "Rendered an unselected crop")
            }
        }
        print("Passed review pane selection, crop preparation, cache reuse, and clipboard preservation")
    }

    private static func collectionViews(in view: NSView) -> [ReviewCollectionView] {
        if let grid = view as? ReviewCollectionView { return [grid] }
        return view.subviews.flatMap { collectionViews(in: $0) }
    }
}
