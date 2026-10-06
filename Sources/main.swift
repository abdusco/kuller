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
if let appIcon = KullerBranding.appIcon {
    app.applicationIconImage = appIcon
}

let delegate = AppDelegate()
app.delegate = delegate
installMainMenu()

let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
let defaultReviewSize = NSSize(width: 1100, height: 750)

/// Smallest the review window may get: exactly one thumbnail column per side
/// (any narrower and NSCollectionViewFlowLayout has no valid layout and logs
/// about it), plus enough height for the toolbar, both headers and one row.
let reviewMinWindowSize = NSSize(
    width: ImageGridMetrics.minimumColumnWidth * 2 + 1,
    height: 40 + 40 + ImageGridMetrics.itemSize.height + ImageGridMetrics.inset * 2 + 28
)

/// Fits `imageSize` within a comfortable fraction of the screen, preserving
/// its aspect ratio.
func fittedWindowSize(forImageSize imageSize: CGSize) -> NSSize {
    guard imageSize.width > 0, imageSize.height > 0 else { return defaultReviewSize }
    let maxSize = NSSize(width: visibleFrame.width * 0.85, height: visibleFrame.height * 0.85)
    let scale = min(maxSize.width / imageSize.width, maxSize.height / imageSize.height)
    return NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
}

// MARK: - Canvas window: grows with the image until it reaches the screen
// edges, then clips the image for internal zoom and pan.

let firstImageSize = appState.currentItem.flatMap { ThumbnailCache.quickPixelSize(of: $0.url) }
var canvasImageSize = firstImageSize ?? defaultReviewSize
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
    // An image decode started during culling can finish after the review
    // screen has taken over the window. Applying it then re-locked the review
    // window to the image's aspect ratio and dropped its minimum size back to
    // the tiny culling one, which is how review could be squashed to a sliver.
    guard appState.phase == .culling else { return }
    // The crop tool has already grown the window by a fixed margin; letting
    // this run mid-crop (e.g. a decode finishing late) would fight that.
    guard !appState.isCropping else { return }
    canvasImageSize = imageSize
    appState.cullingImageSize = nil
    appState.cullingImageOffset = .zero
    canvasWindow.minSize = NSSize(width: 120, height: 90)
    canvasWindow.aspectRatio = imageSize
    let newSize = fittedWindowSize(forImageSize: imageSize)
    let center = CGPoint(x: canvasWindow.frame.midX, y: canvasWindow.frame.midY)
    let newFrame = NSRect(
        x: center.x - newSize.width / 2,
        y: center.y - newSize.height / 2,
        width: newSize.width,
        height: newSize.height
    )
    // Let AppKit draw on its next display pass instead of forcing the
    // hosting view to render synchronously while an image update is applied.
    canvasWindow.setFrame(newFrame, display: false, animate: false)
}

/// Scales the image even after one or both window axes reach the screen.
func scaleCanvasWindow(byFactor factor: CGFloat) {
    let current = canvasWindow.frame
    guard current.width > 0, current.height > 0, factor.isFinite, factor > 0 else { return }
    let screen = canvasWindow.screen?.visibleFrame ?? visibleFrame
    let imageSize = appState.cullingImageSize ?? current.size
    let minimumScale = max(140 / imageSize.width, 105 / imageSize.height)
    let maximumScale = max(screen.width / imageSize.width, screen.height / imageSize.height) * 16
    let scale = min(max(factor, minimumScale), maximumScale)
    guard abs(scale - 1) > 0.00001 else { return }
    let newSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    let newFrame = zoomedCanvasFrame(imageSize: newSize, around: current, within: screen)
    // An aspect lock would keep the shorter axis from growing once the
    // longer axis hits the screen edge. Restore it on zoom-out to a size
    // where the whole image fits in the window again.
    if newSize.width > screen.width || newSize.height > screen.height {
        canvasWindow.resizeIncrements = NSSize(width: 1, height: 1)
    } else {
        canvasWindow.aspectRatio = canvasImageSize
    }
    appState.cullingImageSize = newSize
    canvasWindow.setFrame(newFrame, display: true, animate: false)
    appState.cullingImageOffset = clampedImageOffset(
        CGSize(width: appState.cullingImageOffset.width * scale,
               height: appState.cullingImageOffset.height * scale),
        imageSize: newSize, viewport: canvasWindow.frame.size
    )
}

/// Switches the canvas back to a normal, freely-resizable window for the
/// review screen (no image to lock the aspect ratio to).
func resizeCanvasWindowForReview() {
    appState.cullingImageSize = nil
    appState.cullingImageOffset = .zero
    // Clear the aspect-ratio lock by setting resizeIncrements, which AppKit
    // documents as mutually exclusive with it. Assigning .zero to aspectRatio
    // instead leaves the constraint installed with a degenerate ratio, and
    // dragging an edge then divides by it and traps on the resulting frame.
    canvasWindow.resizeIncrements = NSSize(width: 1, height: 1)
    canvasWindow.minSize = reviewMinWindowSize
    let center = CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
    let newFrame = NSRect(
        x: center.x - defaultReviewSize.width / 2,
        y: center.y - defaultReviewSize.height / 2,
        width: defaultReviewSize.width,
        height: defaultReviewSize.height
    )
    canvasWindow.setFrame(newFrame, display: true, animate: false)
}

/// While cropping, the canvas window temporarily covers the whole screen
/// with an 80%-black backdrop (drawn by CropOverlayView) and the image
/// centered within it, padded on all sides — giving a drag started outside
/// the image's true edge somewhere to land, and a much bigger canvas to
/// work with than the image's normal small culling window. Interactive
/// resizing is disabled for the duration since there's no meaningful
/// "resize" of a screen-covering window.
var canvasFrameBeforeCrop: NSRect?

func enterCropWindowMode() {
    guard appState.phase == .culling, canvasFrameBeforeCrop == nil else { return }
    canvasFrameBeforeCrop = canvasWindow.frame
    canvasWindow.styleMask.remove(.resizable)
    canvasWindow.setFrame(visibleFrame, display: true, animate: false)
    // The title bar itself (not just HoverTrackingHostingView's own drag
    // handling, which only gates the content view) can still be
    // click-dragged by AppKit's default window behavior, and the traffic
    // lights have no purpose on a screen-covering crop overlay — hide both.
    canvasWindow.isMovable = false
    for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
        canvasWindow.standardWindowButton(button)?.isHidden = true
    }
}

func exitCropWindowMode() {
    guard let saved = canvasFrameBeforeCrop else { return }
    canvasWindow.styleMask.insert(.resizable)
    // The crop view is still pinned during this restore. Draw once SwiftUI
    // has also switched back to the viewer, rather than mid-transition.
    canvasWindow.setFrame(saved, display: false, animate: false)
    canvasFrameBeforeCrop = nil
    canvasWindow.isMovable = true
    for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
        canvasWindow.standardWindowButton(button)?.isHidden = false
    }
}

let canvasWindowDelegate = CanvasWindowDelegate(appState: appState)
canvasWindow.delegate = canvasWindowDelegate

let canvasHostingView = HoverTrackingHostingView(rootView: RootView(appState: appState))
// NSHostingView otherwise pushes the SwiftUI content's own measurements into
// the window as contentMinSize/contentMaxSize, which silently overrides the
// window's minSize and (during culling) fights the aspect-ratio lock. All
// sizing here is driven from the window side, so opt out entirely.
canvasHostingView.sizingOptions = []
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
canvasHostingView.allowsWindowInteraction = { appState.phase == .culling && !appState.isCropping }
canvasHostingView.onMagnify = { magnification in
    scaleCanvasWindow(byFactor: 1 + magnification)
}
canvasHostingView.onResetSize = {
    resizeCanvasWindow(toImageSize: canvasImageSize)
}
canvasHostingView.allowsImagePanning = {
    guard let size = appState.cullingImageSize else { return false }
    return size.width > canvasWindow.frame.width + 0.5 || size.height > canvasWindow.frame.height + 0.5
}
canvasHostingView.onPan = { delta in
    guard let size = appState.cullingImageSize else { return }
    appState.cullingImageOffset = clampedImageOffset(
        CGSize(width: appState.cullingImageOffset.width + delta.width,
               height: appState.cullingImageOffset.height + delta.height),
        imageSize: size, viewport: canvasWindow.frame.size
    )
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
        canvasWindow.appearance = nil
    case .review:
        canvasWindow.styleMask.remove(.fullSizeContentView)
        canvasWindow.titlebarAppearsTransparent = false
        // The review screen paints its own near-black backdrop, so force dark
        // appearance: under the system light appearance the labels and the
        // button render near-black on near-black and vanish.
        canvasWindow.appearance = NSAppearance(named: .darkAqua)
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

appState.$isCropping
    .sink { cropping in
        // @Published fires in willSet; deferring keeps this consistent with
        // the $phase sink below, for the same reason.
        DispatchQueue.main.async {
            guard appState.isCropping == cropping else { return }
            if cropping {
                // The sidebar floats above canvasWindow at the screen's
                // literal left edge; once cropping makes the canvas cover
                // the whole screen too, the sidebar would otherwise sit on
                // top of (and obscure) its left edge.
                sidebarWindow.orderOut(nil)
                enterCropWindowMode()
            } else {
                exitCropWindowMode()
                if appState.phase == .culling {
                    sidebarWindow.orderFront(nil)
                }
            }
        }
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
                    PicksExport.copyPicks(appState.picks, cropRects: appState.cropRects, to: destination)
                    NSApp.terminate(nil)
                }
            }
        }
    }
    .store(in: &cancellables)

app.activate(ignoringOtherApps: true)
app.run()
