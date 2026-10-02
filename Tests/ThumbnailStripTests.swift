import AppKit
import SwiftUI

@main
enum ThumbnailStripTests {
    static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuller-strip-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var urls: [URL] = []
        for (index, size) in [(32, 16), (16, 32), (24, 24)].enumerated() {
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: size.0, pixelsHigh: size.1,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )!
            let url = directory.appendingPathComponent("\(index).png")
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
            urls.append(url)
        }
        let items = (0..<600).map { ImageItem(url: urls[$0 % urls.count]) }
        let state = AppState(items: items)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 140, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: ThumbnailStripView(appState: state))
        hosting.sizingOptions = []
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        guard let table = findTable(in: hosting) else { preconditionFailure("No thumbnail table") }

        // Walk in both directions and jump across the list while asynchronous
        // metadata and thumbnail callbacks arrive and cells are reused.
        let indices = Array(items.indices) + Array(items.indices.reversed()) + [599, 0, 300, 599, 0]
        for index in indices {
            state.currentIndex = index
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            precondition(table.selectedRow == index, "Selection lost at \(index): \(table.selectedRow)")
        }
        precondition(table.numberOfRows == items.count)
        precondition(state.currentIndex == 0, "Programmatic selection fed back into navigation")

        let copy = state.insertVirtualCopy(of: items[0], cropRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
        state.jumpTo(copy)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        precondition(table.numberOfRows == 601 && table.selectedRow == 1)
        let originalHeight = table.rect(ofRow: 0).height - table.intercellSpacing.height
        let cropHeight = table.rect(ofRow: 1).height - table.intercellSpacing.height
        precondition(abs(cropHeight - originalHeight * 2) < 1, "Crop row has wrong aspect ratio: \(originalHeight), \(cropHeight)")

        state.removeVirtualCopy(copy)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        precondition(table.numberOfRows == 600 && table.selectedRow == state.currentIndex)

        table.selectRowIndexes(IndexSet(integer: 5), byExtendingSelection: false)
        precondition(state.currentIndex == 5, "Click selection did not navigate")
        print("Passed \(indices.count) navigation updates, crop insertion/removal, row sizing, and selection")
    }

    private static func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for child in view.subviews {
            if let table = findTable(in: child) { return table }
        }
        return nil
    }
}
