import AppKit

@main
enum CropOverlayTests {
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let overlay = CropOverlayNSView(frame: CGRect(x: 0, y: 0, width: 1200, height: 900))
        window.contentView = overlay
        let cases: [(String, CGPoint, CGPoint)] = [
            ("bottom left", CGPoint(x: 0, y: 0), CGPoint(x: -2, y: -2)),
            ("bottom right", CGPoint(x: 1, y: 0), CGPoint(x: 3, y: -2)),
            ("top left", CGPoint(x: 0, y: 1), CGPoint(x: -2, y: 3)),
            ("top right", CGPoint(x: 1, y: 1), CGPoint(x: 3, y: 3)),
            ("left edge", CGPoint(x: 0, y: 0.5), CGPoint(x: -2, y: 0.5)),
            ("right edge", CGPoint(x: 1, y: 0.5), CGPoint(x: 3, y: 0.5)),
            ("bottom edge", CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: -2)),
            ("top edge", CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 3)),
            ("move down left", CGPoint(x: 0.5, y: 0.5), CGPoint(x: -2, y: -2)),
            ("move up right", CGPoint(x: 0.5, y: 0.5), CGPoint(x: 3, y: 3)),
        ]
        var count = 0
        for imageAspect: CGFloat in [0.25, 1, 4] {
            for ratio in CropAspectRatio.allCases {
                for (name, handle, destination) in cases {
                    let session = CropSession()
                    session.begin(committedRect: NormalizedRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
                                  imageAspect: imageAspect, availableSize: overlay.bounds.size)
                    session.setAspectRatio(ratio)
                    overlay.session = session
                    let start = session.rect!
                    let point = CGPoint(x: start.x + start.width * handle.x,
                                        y: start.y + start.height * handle.y)
                    drag(overlay, from: point, to: destination, window: window)
                    let result = session.rect!
                    check(result, ratio: session.normalizedTargetRatio, name: "\(name), \(ratio), \(imageAspect)")
                    if handle.x != 0.5 || handle.y != 0.5 {
                        if let target = session.normalizedTargetRatio {
                            precondition(abs(result.width - min(1, target)) < 1e-9
                                         && abs(result.height - min(1, 1 / target)) < 1e-9,
                                         "Overshoot did not grow the crop to the largest fitting size")
                        } else {
                            if handle.x != 0.5 { precondition(abs(result.width - 1) < 1e-9) }
                            if handle.y != 0.5 { precondition(abs(result.height - 1) < 1e-9) }
                        }
                    }
                    count += 1
                }

                for anchor in [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                               CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 0.5, y: 0.5)] {
                    let session = CropSession()
                    session.begin(committedRect: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                                  imageAspect: imageAspect, availableSize: overlay.bounds.size)
                    session.aspectRatio = ratio
                    overlay.session = session
                    let destination = CGPoint(x: anchor.x == 0 ? 3 : -2, y: anchor.y == 0 ? 3 : -2)
                    drag(overlay, from: anchor, to: destination, window: window)
                    check(session.rect!, ratio: session.normalizedTargetRatio, name: "draw, \(ratio), \(imageAspect)")
                    let target = session.normalizedTargetRatio ?? 1
                    precondition(abs(session.rect!.width - min(1, target)) < 1e-9
                                 && abs(session.rect!.height - min(1, 1 / target)) < 1e-9,
                                 "Drawing from the middle did not grow to the image bounds")
                    count += 1
                }
            }
        }
        let tinyCases: [(String, NormalizedRect, CGPoint, CGPoint)] = [
            ("tiny left edge", NormalizedRect(x: 0, y: 0.3, width: 0.005, height: 0.4),
             CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)),
            ("tiny right edge", NormalizedRect(x: 0.995, y: 0.3, width: 0.005, height: 0.4),
             CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5)),
            ("tiny bottom edge", NormalizedRect(x: 0.3, y: 0, width: 0.4, height: 0.005),
             CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)),
            ("tiny top edge", NormalizedRect(x: 0.3, y: 0.995, width: 0.4, height: 0.005),
             CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0)),
        ]
        for (name, rect, handle, destination) in tinyCases {
            let session = CropSession()
            session.begin(committedRect: rect, imageAspect: 1, availableSize: overlay.bounds.size)
            session.aspectRatio = .free
            overlay.session = session
            let point = CGPoint(x: rect.x + rect.width * handle.x, y: rect.y + rect.height * handle.y)
            drag(overlay, from: point, to: destination, window: window)
            check(session.rect!, ratio: nil, name: name)
            count += 1
        }
        // Grow past the top/right boundary in one continuous drag, then
        // reverse direction. The crop should shrink back without jumping.
        for ratio in [CropAspectRatio.free, .original] {
            let session = CropSession()
            session.begin(committedRect: NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
                          imageAspect: 1, availableSize: overlay.bounds.size)
            session.aspectRatio = ratio
            overlay.session = session
            let imageRect = cropImageRect(pinnedSize: session.pinnedImageSize, in: overlay.bounds)
            let steps: [(NSEvent.EventType, CGFloat, CGFloat, CGFloat)] = [
                (.leftMouseDown, 0.6, 0.2, 0.4),
                (.leftMouseDragged, 0.9, 0.2, 0.7),
                (.leftMouseDragged, 1, 0.2, 0.8),
                (.leftMouseDragged, 1.1, 0.1, 0.9),
                (.leftMouseDragged, 1.5, 0, 1),
                (.leftMouseDragged, 1.1, 0.1, 0.9),
                (.leftMouseDragged, 0.9, 0.2, 0.7),
            ]
            for (type, pointer, origin, size) in steps {
                let point = CGPoint(x: imageRect.minX + pointer * imageRect.width,
                                    y: imageRect.minY + pointer * imageRect.height)
                let event = NSEvent.mouseEvent(with: type, location: overlay.convert(point, to: nil),
                                              modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                if type == .leftMouseDown { overlay.mouseDown(with: event) }
                else { overlay.mouseDragged(with: event) }
                let rect = session.rect!
                precondition(abs(rect.x - origin) < 1e-9 && abs(rect.y - origin) < 1e-9
                             && abs(rect.width - size) < 1e-9 && abs(rect.height - size) < 1e-9,
                             "Crop did not grow and reverse smoothly at pointer \(pointer): \(rect)")
                count += 1
            }
        }
        print("Passed \(count) crop bounds, aspect ratio, and overshoot growth cases")
    }

    private static func drag(_ overlay: CropOverlayNSView, from start: CGPoint, to end: CGPoint, window: NSWindow) {
        let imageRect = cropImageRect(pinnedSize: overlay.session!.pinnedImageSize, in: overlay.bounds)
        for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
            let viewPoint = CGPoint(x: imageRect.minX + point.x * imageRect.width,
                                    y: imageRect.minY + point.y * imageRect.height)
            let event = NSEvent.mouseEvent(with: type, location: overlay.convert(viewPoint, to: nil),
                                          modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            switch type {
            case .leftMouseDown: overlay.mouseDown(with: event)
            case .leftMouseDragged: overlay.mouseDragged(with: event)
            default: overlay.mouseUp(with: event)
            }
        }
    }

    private static func check(_ rect: NormalizedRect, ratio: CGFloat?, name: String) {
        precondition(rect.x >= -1e-9 && rect.y >= -1e-9 && rect.width > 0 && rect.height > 0
                     && rect.x + rect.width <= 1 + 1e-9 && rect.y + rect.height <= 1 + 1e-9,
                     "\(name): crop escaped image bounds: \(rect)")
        if let ratio {
            precondition(abs(rect.width / rect.height - ratio) < 1e-9, "\(name): crop lost aspect ratio")
        }
    }
}
