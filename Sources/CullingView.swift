import SwiftUI
import AppKit

struct CullingView: View {
    @ObservedObject var appState: AppState
    @StateObject private var cropSession = CropSession()
    @State private var keyMonitor: KeyMonitor?

    var body: some View {
        ZStack {
            ImageViewerView(
                item: appState.currentItem,
                pinnedSize: appState.isCropping ? cropSession.pinnedImageSize : nil,
                cropRect: appState.isCropping ? nil : appState.currentItem.flatMap { appState.cropRects[$0.id] }
            )
            if appState.isCropping {
                CropOverlayView(session: cropSession, onCommit: commitCrop, onCancel: cancelCrop)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if appState.isCropping {
                cropToolbar
            }
        }
        .overlay(alignment: .bottom) {
            if appState.isCropping {
                cropHint
            }
        }
        .onAppear {
            keyMonitor = KeyMonitor { [appState] event in
                handleKeyDown(event, appState: appState)
            }
        }
        .onDisappear {
            keyMonitor?.stop()
            keyMonitor = nil
        }
    }

    // MARK: Crop toolbar

    /// Behaves like a real menu bar: floats above the crop overlay so its
    /// one real control (the ratio menu) stays clickable, but the rest of
    /// the strip lets clicks/drags fall through to the crop overlay behind
    /// it — so a crop selection can be started from the very top edge of
    /// the screen without needing to start inside the image first.
    private var cropToolbar: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(CropAspectRatio.allCases, id: \.self) { ratio in
                    Button {
                        cropSession.setAspectRatio(ratio)
                    } label: {
                        if ratio == cropSession.aspectRatio {
                            Label(ratio.label, systemImage: "checkmark")
                        } else {
                            Text(ratio.label)
                        }
                    }
                }
            } label: {
                Label(cropSession.aspectRatio.label, systemImage: "aspectratio")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.accessoryBar)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .allowsHitTesting(true)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .allowsHitTesting(false)
    }

    /// Purely informational, so it sits on the backdrop rather than the
    /// toolbar — doesn't intercept clicks/drags either, same reasoning as
    /// `cropToolbar`.
    private var cropHint: some View {
        Text("⌥+/‑ or ⌥1-9/0 ratio  ·  ⏎ confirm  ·  esc cancel")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.bottom, 16)
            .allowsHitTesting(false)
    }

    // MARK: Crop actions

    private func enterCropMode() {
        guard let current = appState.currentItem else { return }
        let imageAspect = ThumbnailCache.quickPixelSize(of: current.url).map { $0.width / $0.height } ?? 1
        cropSession.begin(committedRect: appState.cropRects[current.id], imageAspect: imageAspect, availableSize: visibleFrame.size)
        appState.isCropping = true
    }

    /// A fresh crop on an original creates a new virtual copy rather than
    /// mutating the original (so the source stays browsable uncropped); a
    /// crop refined on an existing virtual copy just updates it in place,
    /// so re-adjusting the same copy doesn't spawn a copy-of-a-copy chain.
    /// An untouched Return (rect still the full image) on an original is a
    /// no-op — no point in a duplicate identical to its source.
    private func commitCrop() {
        defer { appState.isCropping = false }
        guard let current = appState.currentItem, let rect = cropSession.rect else { return }
        if current.isVirtualCopy {
            appState.cropRects[current.id] = rect
        } else if rect != .fullImage {
            let copy = appState.insertVirtualCopy(of: current, cropRect: rect)
            appState.jumpTo(copy)
        }
    }

    private func cancelCrop() {
        appState.isCropping = false
    }

    // MARK: Keyboard

    private func handleKeyDown(_ event: NSEvent, appState: AppState) -> Bool {
        if handleCropKeyDown(event, appState: appState) {
            return true
        }
        if handleGlobalShortcuts(event, appState: appState) {
            return true
        }

        let leftArrow: UInt16 = 123
        let rightArrow: UInt16 = 124
        let returnKey: UInt16 = 36

        if event.modifierFlags.contains(.command), event.keyCode == returnKey {
            appState.submit()
            return true
        }

        if event.keyCode == leftArrow {
            appState.goToPrevious()
            return true
        }

        if event.keyCode == rightArrow {
            appState.goToNext()
            return true
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch characters {
        case "j":
            appState.goToNext()
            return true
        case "k":
            appState.goToPrevious()
            return true
        default:
            break
        }

        guard let current = appState.currentItem else { return false }

        switch characters {
        case "p":
            appState.decide(current, .pick)
            return true
        case "x":
            appState.decide(current, .reject)
            return true
        default:
            return false
        }
    }

    /// Checked before every other key handler in culling, so an active crop
    /// swallows all input (Esc cancels the crop rather than triggering the
    /// quit-confirmation, arrows/j/k/p/x can't silently abandon it, etc.).
    private func handleCropKeyDown(_ event: NSEvent, appState: AppState) -> Bool {
        let returnKey: UInt16 = 36
        let escapeKey: UInt16 = 53
        let equalsKey: UInt16 = 24
        let minusKey: UInt16 = 27
        // Alt+1...Alt+9 pick a ratio directly; Alt+0 sets Free.
        let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
        let zeroKeyCode: UInt16 = 29

        if !appState.isCropping {
            let noOtherModifiers = event.modifierFlags.isDisjoint(with: [.command, .option, .control])
            if noOtherModifiers, event.charactersIgnoringModifiers?.lowercased() == "c" {
                enterCropMode()
                return true
            }
            return false
        }

        if event.keyCode == returnKey {
            commitCrop()
            return true
        }
        if event.keyCode == escapeKey {
            cancelCrop()
            return true
        }
        if event.modifierFlags.contains(.option), event.keyCode == equalsKey {
            cropSession.cycleAspectRatio(forward: true)
            return true
        }
        if event.modifierFlags.contains(.option), event.keyCode == minusKey {
            cropSession.cycleAspectRatio(forward: false)
            return true
        }
        if event.modifierFlags.contains(.option), event.keyCode == zeroKeyCode {
            cropSession.setAspectRatio(.free)
            return true
        }
        if event.modifierFlags.contains(.option), let digit = digitKeyCodes[event.keyCode] {
            let shortcuts = CropAspectRatio.digitShortcuts
            if digit <= shortcuts.count {
                cropSession.setAspectRatio(shortcuts[digit - 1])
            }
            return true
        }
        return true
    }
}
