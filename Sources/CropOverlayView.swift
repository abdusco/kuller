import AppKit
import SwiftUI

/// The crop tool's mouse handling and drawing, done in AppKit rather than
/// with a SwiftUI DragGesture — following the same reasoning as
/// HoverTrackingHostingView (a gesture's translation is reported in the
/// view's own coordinate space, which invites feedback loops for anything
/// that also moves/resizes; here the drag state and the rect it's editing
/// both live in that same space, so tracking it manually keeps the math in
/// one place).
struct CropOverlayView: NSViewRepresentable {
    @ObservedObject var session: CropSession
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> CropOverlayNSView {
        let view = CropOverlayNSView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: CropOverlayNSView, context: Context) {
        nsView.session = session
        nsView.needsDisplay = true
    }
}

final class CropOverlayNSView: NSView {
    var session: CropSession? {
        didSet { needsDisplay = true }
    }

    private enum DragMode {
        case move(startRect: NormalizedRect, startPoint: CGPoint)
        case resizeCorner(corner: Corner, opposite: CGPoint)
        case resizeEdge(edge: Edge, startRect: NormalizedRect, startPoint: CGPoint)
        case draw(anchor: CGPoint)
    }

    private enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    private enum Edge: CaseIterable { case top, bottom, left, right }

    private var dragMode: DragMode?
    private let handleSize: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let session, let rect = session.rect else { return }
        let imageRect = cropImageRect(pinnedSize: session.pinnedImageSize, in: bounds)
        let cropRectInView = viewRect(for: rect, in: imageRect)

        let outer = NSBezierPath(rect: bounds)
        outer.append(NSBezierPath(rect: cropRectInView))
        outer.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.8).setFill()
        outer.fill()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: cropRectInView)
        border.lineWidth = 1
        border.stroke()

        for corner in Corner.allCases {
            drawHandle(at: handleCenter(for: corner, in: cropRectInView))
        }
        for edge in Edge.allCases {
            drawHandle(at: handleCenter(for: edge, in: cropRectInView))
        }
    }

    private func drawHandle(at center: CGPoint) {
        let rect = CGRect(x: center.x - handleSize / 2, y: center.y - handleSize / 2, width: handleSize, height: handleSize)
        let path = NSBezierPath(rect: rect)
        NSColor.white.setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func handleCenter(for corner: Corner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        }
    }

    private func handleCenter(for edge: Edge, in rect: CGRect) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.minY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        }
    }

    // MARK: Mouse handling

    override func mouseDown(with event: NSEvent) {
        guard let session, let rect = session.rect else { return }
        let point = convert(event.locationInWindow, from: nil)
        let imageRect = cropImageRect(pinnedSize: session.pinnedImageSize, in: bounds)
        let cropRectInView = viewRect(for: rect, in: imageRect)

        for corner in Corner.allCases {
            let center = handleCenter(for: corner, in: cropRectInView)
            if hitTest(point, center: center) {
                let opposite = oppositeCorner(of: corner, in: cropRectInView)
                dragMode = .resizeCorner(corner: corner, opposite: opposite)
                return
            }
        }
        for edge in Edge.allCases {
            let center = handleCenter(for: edge, in: cropRectInView)
            if hitTest(point, center: center) {
                dragMode = .resizeEdge(edge: edge, startRect: rect, startPoint: point)
                return
            }
        }
        if cropRectInView.contains(point) {
            dragMode = .move(startRect: rect, startPoint: point)
        } else {
            dragMode = .draw(anchor: point)
        }
    }

    private func hitTest(_ point: CGPoint, center: CGPoint) -> Bool {
        abs(point.x - center.x) <= handleSize && abs(point.y - center.y) <= handleSize
    }

    private func oppositeCorner(of corner: Corner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: rect.maxX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.minX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.minX, y: rect.maxY)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let session, let dragMode else { return }
        let point = convert(event.locationInWindow, from: nil)
        let imageRect = cropImageRect(pinnedSize: session.pinnedImageSize, in: bounds)
        guard imageRect.width > 0, imageRect.height > 0 else { return }
        // Keep the pointer's overshoot: it grows the crop back toward the
        // opposite edge after the dragged side reaches the image boundary.
        let dragNormalized = CGPoint(x: (point.x - imageRect.minX) / imageRect.width,
                                     y: (point.y - imageRect.minY) / imageRect.height)
        let ratio = session.normalizedTargetRatio

        switch dragMode {
        case .draw(let anchor):
            let a = normalizedPoint(from: anchor, in: imageRect)
            session.rect = rectFrom(a, dragNormalized, ratio: ratio)

        case .move(let startRect, let startPoint):
            let deltaX = (point.x - startPoint.x) / imageRect.width
            let deltaY = (point.y - startPoint.y) / imageRect.height
            var newRect = startRect
            newRect.x = min(max(startRect.x + deltaX, 0), 1 - startRect.width)
            newRect.y = min(max(startRect.y + deltaY, 0), 1 - startRect.height)
            session.rect = newRect

        case .resizeCorner(_, let oppositeView):
            let oppositeNormalized = normalizedPoint(from: oppositeView, in: imageRect)
            session.rect = rectFrom(oppositeNormalized, dragNormalized, ratio: ratio)

        case .resizeEdge(let edge, let startRect, _):
            session.rect = resized(startRect, edge: edge, to: dragNormalized, ratio: ratio)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = nil
    }

    /// Builds a rect from two normalized corner points, optionally
    /// constrained to `ratio`. Grow from the first corner until an edge
    /// hits the image, then shift the rect to accommodate further growth.
    private func rectFrom(_ a: CGPoint, _ b: CGPoint, ratio: CGFloat?) -> NormalizedRect {
        var width = min(abs(b.x - a.x), 1)
        var height = min(abs(b.y - a.y), 1)
        if let ratio {
            width = min(max(abs(b.x - a.x), abs(b.y - a.y) * ratio), 1, ratio)
            height = min(width / ratio, 1)
        }
        let x = b.x >= a.x ? a.x : a.x - width
        let y = b.y >= a.y ? a.y : a.y - height
        return NormalizedRect(x: min(max(x, 0), 1 - width),
                              y: min(max(y, 0), 1 - height),
                              width: width, height: height)
    }

    /// Single-edge resize with the same overshoot growth as corner drags.
    /// Keep the opposite edge fixed until the crop must shift to fit.
    private func resized(_ rect: NormalizedRect, edge: Edge, to point: CGPoint, ratio: CGFloat?) -> NormalizedRect {
        var newRect = rect
        switch edge {
        case .left:
            newRect.width = min(max(rect.x + rect.width - point.x, 0.01), 1)
        case .right:
            newRect.width = min(max(point.x - rect.x, 0.01), 1)
        case .bottom:
            newRect.height = min(max(rect.y + rect.height - point.y, 0.01), 1)
        case .top:
            newRect.height = min(max(point.y - rect.y, 0.01), 1)
        }

        switch edge {
        case .left, .right:
            if let ratio {
                newRect.width = min(newRect.width, ratio)
                newRect.height = min(newRect.width / ratio, 1)
                newRect.y = min(max(rect.y + rect.height / 2 - newRect.height / 2, 0), 1 - newRect.height)
            }
            let x = edge == .left ? rect.x + rect.width - newRect.width : rect.x
            newRect.x = min(max(x, 0), 1 - newRect.width)
        case .top, .bottom:
            if let ratio {
                newRect.height = min(newRect.height, 1 / ratio)
                newRect.width = min(newRect.height * ratio, 1)
                newRect.x = min(max(rect.x + rect.width / 2 - newRect.width / 2, 0), 1 - newRect.width)
            }
            let y = edge == .bottom ? rect.y + rect.height - newRect.height : rect.y
            newRect.y = min(max(y, 0), 1 - newRect.height)
        }
        return newRect
    }
}
