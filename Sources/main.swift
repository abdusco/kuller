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
installMainMenu()

let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
let defaultReviewSize = NSSize(width: 1100, height: 750)

/// Fits `imageSize` within a comfortable fraction of the screen, preserving
/// its aspect ratio.
func fittedWindowSize(forImageSize imageSize: CGSize) -> NSSize {
    guard imageSize.width > 0, imageSize.height > 0 else { return defaultReviewSize }
    let maxSize = NSSize(width: visibleFrame.width * 0.85, height: visibleFrame.height * 0.85)
    let scale = min(maxSize.width / imageSize.width, maxSize.height / imageSize.height)
    return NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
}

// MARK: - Canvas window: the window IS the image (Preview/Photoshop-style),
// not a fixed pane with internal pan/zoom. Its size/aspect always matches
// the current image; dragging the image moves this window, pinching
// resizes it (see ImageViewerView). That gets a real title bar with
// traffic lights and the standard AppKit drop shadow for free.

let firstImageSize = appState.currentItem.flatMap { ThumbnailCache.quickPixelSize(of: $0.url) }
let initialCanvasSize = fittedWindowSize(forImageSize: firstImageSize ?? defaultReviewSize)
let canvasFrame = NSRect(
    x: visibleFrame.midX - initialCanvasSize.width / 2,
    y: visibleFrame.midY - initialCanvasSize.height / 2,
    width: initialCanvasSize.width,
    height: initialCanvasSize.height
)

let canvasWindow = NSWindow(
    contentRect: canvasFrame,
    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
    backing: .buffered,
    defer: false
)
// Keep minSize tiny: a large minimum would stop the window from taking a
// narrow/short shape for extreme aspect ratios, and would make AppKit
// silently enlarge frames we set (which drifts the window's position).
canvasWindow.minSize = NSSize(width: 120, height: 90)
canvasWindow.title = "kuller"
if let firstImageSize {
    // aspectRatio (frame-based) rather than contentAspectRatio, to stay
    // consistent with the setFrame math used everywhere below.
    canvasWindow.aspectRatio = firstImageSize
}

// Content extends up under the (transparent) title bar, and the title bar
// itself fades in/out based on hover — see HoverTrackingHostingView below.
canvasWindow.titlebarAppearsTransparent = true
canvasWindow.isMovableByWindowBackground = false
canvasWindow.isOpaque = false
canvasWindow.backgroundColor = .clear
canvasWindow.hasShadow = true

/// Resizes the canvas window to fit `imageSize` (keeping its current
/// center) and locks manual edge-resizing to that aspect ratio too.
func resizeCanvasWindow(toImageSize imageSize: CGSize) {
    guard imageSize.width > 0, imageSize.height > 0 else { return }
    canvasWindow.aspectRatio = imageSize
    let newSize = fittedWindowSize(forImageSize: imageSize)
    let center = CGPoint(x: canvasWindow.frame.midX, y: canvasWindow.frame.midY)
    let newFrame = NSRect(
        x: center.x - newSize.width / 2,
        y: center.y - newSize.height / 2,
        width: newSize.width,
        height: newSize.height
    )
    canvasWindow.setFrame(newFrame, display: true, animate: false)
}

/// Scales the canvas window around its center by an incremental factor
/// (from a pinch delta), preserving its current aspect ratio.
func scaleCanvasWindow(byFactor factor: CGFloat) {
    let current = canvasWindow.frame
    guard current.width > 0, current.height > 0, factor > 0 else { return }

    let aspect = current.height / current.width
    let minWidth = max(canvasWindow.minSize.width, 140)
    let minHeight = max(canvasWindow.minSize.height, 105)

    var newWidth = min(max(current.width * factor, minWidth), visibleFrame.width * 3)
    var newHeight = newWidth * aspect
    if newHeight < minHeight {
        newHeight = minHeight
        newWidth = newHeight / aspect
    }

    // Already at a clamp: leave the frame completely alone. Recomputing an
    // origin from a size AppKit then refuses to apply is what made repeated
    // pinching past the minimum walk the window across the screen.
    guard abs(newWidth - current.width) > 0.5 else { return }

    let center = CGPoint(x: current.midX, y: current.midY)
    let newFrame = NSRect(
        x: center.x - newWidth / 2,
        y: center.y - newHeight / 2,
        width: newWidth,
        height: newHeight
    )
    canvasWindow.setFrame(newFrame, display: true, animate: false)
}

/// Switches the canvas back to a normal, freely-resizable window for the
/// review screen (no image to lock the aspect ratio to).
func resizeCanvasWindowForReview() {
    canvasWindow.aspectRatio = .zero
    let center = CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
    let newFrame = NSRect(
        x: center.x - defaultReviewSize.width / 2,
        y: center.y - defaultReviewSize.height / 2,
        width: defaultReviewSize.width,
        height: defaultReviewSize.height
    )
    canvasWindow.setFrame(newFrame, display: true, animate: false)
}

let canvasWindowDelegate = CanvasWindowDelegate(appState: appState)
canvasWindow.delegate = canvasWindowDelegate

let canvasHostingView = HoverTrackingHostingView(rootView: RootView(appState: appState))
canvasHostingView.wantsLayer = true
canvasHostingView.layer?.backgroundColor = NSColor.clear.cgColor
canvasHostingView.onHoverChange = { hovering in
    // Only the image screen hides its chrome on hover-out; the review
    // screen keeps a normal, always-visible title bar.
    guard appState.phase == .culling,
          let titlebarView = canvasWindow.standardWindowButton(.closeButton)?.superview else { return }
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.2
        titlebarView.animator().alphaValue = hovering ? 1 : 0
    }
}
canvasHostingView.allowsWindowInteraction = { appState.phase == .culling }
canvasHostingView.onMagnify = { magnification in
    scaleCanvasWindow(byFactor: 1 + magnification)
}
canvasHostingView.onResetSize = {
    guard let item = appState.currentItem,
          let size = ThumbnailCache.quickPixelSize(of: item.url) else { return }
    resizeCanvasWindow(toImageSize: size)
}
canvasWindow.contentView = canvasHostingView
canvasWindow.makeKeyAndOrderFront(nil)

/// Culling wants an edge-to-edge image behind a transparent, hover-fading
/// title bar; review wants ordinary window chrome with content pushed below
/// an opaque, always-visible title bar.
func configureWindowChrome(for phase: AppPhase) {
    switch phase {
    case .culling:
        canvasWindow.styleMask.insert(.fullSizeContentView)
        canvasWindow.titlebarAppearsTransparent = true
    case .review:
        canvasWindow.styleMask.remove(.fullSizeContentView)
        canvasWindow.titlebarAppearsTransparent = false
        // Undo any leftover fade from hovering out during culling.
        canvasWindow.standardWindowButton(.closeButton)?.superview?.alphaValue = 1
    }
}
configureWindowChrome(for: appState.phase)

/// Keeps the (fading) title bar showing the current image's filename, or
/// "Review" on the review screen. Takes phase/currentItem as parameters
/// rather than re-reading appState directly: @Published fires its
/// subscribers in willSet, before the stored property actually changes, so
/// reading appState.phase/currentItem from inside a sink on that same
/// property would see the stale, pre-change value.
func updateCanvasTitle(phase: AppPhase, currentItem: ImageItem?) {
    switch phase {
    case .culling:
        canvasWindow.title = currentItem?.displayName ?? "kuller"
    case .review:
        canvasWindow.title = "Review"
    }
}
updateCanvasTitle(phase: appState.phase, currentItem: appState.currentItem)

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

// A non-activating panel: it can be clicked without stealing key focus from
// the canvas window, and .hidesOnDeactivate means it gets out of the way
// entirely when you switch to another app — so it never hovers over the
// desktop or Finder while you're dragging files there.
let sidebarWindow = NSPanel(
    contentRect: sidebarFrame,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
sidebarWindow.isMovableByWindowBackground = false
sidebarWindow.isOpaque = false
sidebarWindow.backgroundColor = .clear
sidebarWindow.level = .floating
sidebarWindow.hidesOnDeactivate = true
sidebarWindow.hasShadow = false

let sidebarHostingView = NSHostingView(rootView: ThumbnailStripView(appState: appState))
sidebarHostingView.wantsLayer = true
sidebarHostingView.layer?.backgroundColor = NSColor.clear.cgColor
sidebarWindow.contentView = sidebarHostingView
sidebarWindow.orderFront(nil)

var cancellables: Set<AnyCancellable> = []

appState.$currentIndex
    .sink { newIndex in
        let item = appState.items.indices.contains(newIndex) ? appState.items[newIndex] : nil
        updateCanvasTitle(phase: appState.phase, currentItem: item)
    }
    .store(in: &cancellables)

// The sidebar only makes sense during culling; hide it on the review screen.
// If --copy-picks-to was given, skip the review screen entirely: copy picks
// straight to that directory and quit as soon as culling is done.
appState.$phase
    .sink { newPhase in
        updateCanvasTitle(phase: newPhase, currentItem: appState.currentItem)
        // @Published fires in willSet, so this runs before appState.phase
        // actually flips and before SwiftUI re-renders the view tree.
        // Reconfiguring/resizing the window at that point left the hosting
        // view showing stale culling content until some later event forced a
        // redraw — hence deferring to the next main-queue turn.
        DispatchQueue.main.async {
            configureWindowChrome(for: newPhase)
            switch newPhase {
            case .culling:
                sidebarWindow.orderFront(nil)
                if let item = appState.currentItem,
                   let size = ThumbnailCache.quickPixelSize(of: item.url) {
                    resizeCanvasWindow(toImageSize: size)
                }
            case .review:
                sidebarWindow.orderOut(nil)
                resizeCanvasWindowForReview()
                if let destination = copyPicksToURL {
                    PicksExport.copyPicks(appState.picks, to: destination)
                    NSApp.terminate(nil)
                }
            }
        }
    }
    .store(in: &cancellables)

app.activate(ignoringOtherApps: true)
app.run()
