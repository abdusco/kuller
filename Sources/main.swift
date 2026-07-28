import AppKit
import SwiftUI
import Combine

let arguments = Array(CommandLine.arguments.dropFirst())
guard let cliResult = CLI.run(arguments: arguments) else {
    exit(0)
}

let appState = AppState(items: cliResult.images)
let copyPicksToURL = cliResult.copyPicksTo

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate = AppDelegate()
app.delegate = delegate

// Use the screen's full frame (not visibleFrame) so the window extends
// under the menu bar and covers the entire display.
let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
let visibleFrame = NSScreen.main?.visibleFrame ?? screenFrame

// MARK: - Canvas window: full-display, borderless, transparent, holds the
// pannable/zoomable image viewer (and the review screen).

let canvasWindow = BorderlessKeyWindow(
    contentRect: screenFrame,
    styleMask: [.borderless, .resizable],
    backing: .buffered,
    defer: false
)
canvasWindow.title = "kuller"
canvasWindow.setFrame(screenFrame, display: true)

// The window always covers the full display, so it never needs to be
// dragged around — leaving background-drag off avoids fighting with the
// image viewer's own pan gesture.
canvasWindow.isMovableByWindowBackground = false

// Let the desktop/other windows show through the content area (not a real
// fullscreen space, just a big regular window) so images float against
// whatever's behind them instead of an opaque backdrop.
canvasWindow.isOpaque = false
canvasWindow.backgroundColor = .clear
canvasWindow.level = .normal

let canvasHostingView = NSHostingView(rootView: RootView(appState: appState))
canvasHostingView.wantsLayer = true
canvasHostingView.layer?.backgroundColor = NSColor.clear.cgColor
canvasWindow.contentView = canvasHostingView
canvasWindow.makeKeyAndOrderFront(nil)

// MARK: - Sidebar window: a separate panel docked to the left edge of the
// screen, always floating above the canvas, transparent like the canvas.
// Independent of the canvas window so panning/zooming the image never
// drags or otherwise affects it.

let sidebarWidth: CGFloat = 140
let sidebarFrame = NSRect(
    x: visibleFrame.minX,
    y: visibleFrame.minY,
    width: sidebarWidth,
    height: visibleFrame.height
)

let sidebarWindow = BorderlessKeyWindow(
    contentRect: sidebarFrame,
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
sidebarWindow.isMovableByWindowBackground = false
sidebarWindow.isOpaque = false
sidebarWindow.backgroundColor = .clear
sidebarWindow.level = .floating
sidebarWindow.hasShadow = false

let sidebarHostingView = NSHostingView(rootView: ThumbnailStripView(appState: appState))
sidebarHostingView.wantsLayer = true
sidebarHostingView.layer?.backgroundColor = NSColor.clear.cgColor
sidebarWindow.contentView = sidebarHostingView
sidebarWindow.orderFront(nil)

// The sidebar only makes sense during culling; hide it on the review screen.
// If --copy-picks-to was given, skip the review screen entirely: copy picks
// straight to that directory and quit as soon as culling is done.
var sidebarPhaseObserver: AnyCancellable? = appState.$phase.sink { phase in
    switch phase {
    case .culling:
        sidebarWindow.orderFront(nil)
    case .review:
        sidebarWindow.orderOut(nil)
        if let destination = copyPicksToURL {
            PicksExport.copyPicks(appState.picks, to: destination)
            NSApp.terminate(nil)
        }
    }
}

app.activate(ignoringOtherApps: true)
app.run()
