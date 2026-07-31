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
        let ratio = session.normalizedTargetRatio

        switch dragMode {
        case .draw(let anchor):
            let a = normalizedPoint(from: anchor, in: imageRect)
            let b = normalizedPoint(from: point, in: imageRect)
            session.rect = rectFrom(a, b, ratio: ratio)

        case .move(let startRect, let startPoint):
            let deltaX = (point.x - startPoint.x) / imageRect.width
            let deltaY = (point.y - startPoint.y) / imageRect.height
            var newRect = startRect
            newRect.x = min(max(startRect.x + deltaX, 0), 1 - startRect.width)
            newRect.y = min(max(startRect.y + deltaY, 0), 1 - startRect.height)
            session.rect = newRect

        case .resizeCorner(_, let oppositeView):
            let oppositeNormalized = normalizedPoint(from: oppositeView, in: imageRect)
            let dragNormalized = normalizedPoint(from: point, in: imageRect)
            session.rect = rectFrom(oppositeNormalized, dragNormalized, ratio: ratio)

        case .resizeEdge(let edge, let startRect, _):
            let dragNormalized = normalizedPoint(from: point, in: imageRect)
            session.rect = resized(startRect, edge: edge, to: dragNormalized, ratio: ratio)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = nil
    }

    /// Builds a rect from two normalized corner points, optionally
    /// constrained to `ratio` (driven off the larger axis delta so the
    /// result never exceeds either corner's bounds).
    private func rectFrom(_ a: CGPoint, _ b: CGPoint, ratio: CGFloat?) -> NormalizedRect {
        var minX = min(a.x, b.x)
        var maxX = max(a.x, b.x)
        var minY = min(a.y, b.y)
        var maxY = max(a.y, b.y)

        if let ratio {
            let width = maxX - minX
            let height = maxY - minY
            let anchorX = a.x
            let anchorY = a.y
            if width / max(height, 0.0001) > ratio {
                let newHeight = width / ratio
                if b.y >= anchorY {
                    maxY = min(anchorY + newHeight, 1)
                    minY = maxY - newHeight
                } else {
                    minY = max(anchorY - newHeight, 0)
                    maxY = minY + newHeight
                }
            } else {
                let newWidth = height * ratio
                if b.x >= anchorX {
                    maxX = min(anchorX + newWidth, 1)
                    minX = maxX - newWidth
                } else {
                    minX = max(anchorX - newWidth, 0)
                    maxX = minX + newWidth
                }
            }
        }

        return NormalizedRect(x: minX, y: minY, width: max(maxX - minX, 0), height: max(maxY - minY, 0))
    }

    /// Single-edge resize: moves only the dragged edge, anchored at the
    /// opposite edge, clamped to 0...1. When `ratio` is set, the
    /// perpendicular dimension is derived from it and centered on the
    /// rect's current center on that axis (shifted, then shrunk only if it
    /// still can't fit within 0...1 after shifting).
    private func resized(_ rect: NormalizedRect, edge: Edge, to point: CGPoint, ratio: CGFloat?) -> NormalizedRect {
        var newRect = rect
        switch edge {
        case .left:
            let newX = min(max(point.x, 0), rect.x + rect.width - 0.01)
            newRect.width = rect.x + rect.width - newX
            newRect.x = newX
        case .right:
            let newMaxX = max(min(point.x, 1), rect.x + 0.01)
            newRect.width = newMaxX - rect.x
        case .bottom:
            let newY = min(max(point.y, 0), rect.y + rect.height - 0.01)
            newRect.height = rect.y + rect.height - newY
            newRect.y = newY
        case .top:
            let newMaxY = max(min(point.y, 1), rect.y + 0.01)
            newRect.height = newMaxY - rect.y
        }

        guard let ratio else { return newRect }

        switch edge {
        case .left, .right:
            var height = newRect.width / ratio
            let centerY = rect.y + rect.height / 2
            var y = centerY - height / 2
            if y < 0 { y = 0 }
            if y + height > 1 { y = max(0, 1 - height) }
            if height > 1 {
                height = 1
                y = 0
                newRect.width = height * ratio
                if edge == .right { newRect.width = min(newRect.width, 1 - newRect.x) }
                else {
                    let anchorX = rect.x + rect.width
                    newRect.x = max(0, anchorX - newRect.width)
                }
            }
            newRect.y = y
            newRect.height = height
        case .top, .bottom:
            var width = newRect.height * ratio
            let centerX = rect.x + rect.width / 2
            var x = centerX - width / 2
            if x < 0 { x = 0 }
            if x + width > 1 { x = max(0, 1 - width) }
            if width > 1 {
                width = 1
                x = 0
                newRect.height = width / ratio
                if edge == .top { newRect.height = min(newRect.height, 1 - newRect.y) }
                else {
                    let anchorY = rect.y + rect.height
                    newRect.y = max(0, anchorY - newRect.height)
                }
            }
            newRect.x = x
            newRect.width = width
        }
        return newRect
    }
}
