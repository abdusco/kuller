import SwiftUI
import AppKit

struct CullingView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var preferences = AppPreferences.shared
    @StateObject private var cropSession = CropSession()
    @State private var keyMonitor: KeyMonitor?
    @State private var imageProperties: ImageProperties?
    @State private var propertiesFlashID = UUID()

    var body: some View {
        ZStack {
            ImageViewerView(
                item: appState.currentItem,
                pinnedSize: appState.isCropping ? cropSession.pinnedImageSize : nil,
                cropRect: appState.isCropping ? nil : appState.currentItem.flatMap { appState.cropRects[$0.id] },
                zoomedSize: appState.isCropping ? nil : appState.cullingImageSize,
                zoomOffset: appState.isCropping ? .zero : appState.cullingImageOffset
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
        .overlay(alignment: .bottomTrailing) {
            if let imageProperties {
                ImagePropertiesView(properties: imageProperties)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: imageProperties != nil)
        .task(id: propertiesFlashID) {
            guard imageProperties != nil else { return }
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            imageProperties = nil
        }
        .onChange(of: appState.currentItem?.id) { _, _ in
            dismissImageProperties()
        }
        .onChange(of: appState.isCropping) { _, _ in
            dismissImageProperties()
        }
        .onAppear {
            keyMonitor = KeyMonitor { [appState] event in
                handleKeyDown(event, appState: appState)
            }
        }
        .onDisappear {
            dismissImageProperties()
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
                ForEach(preferences.cropPresets, id: \.self) { ratio in
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
        Text("\(preferences.hint(.nextRatio)) / \(preferences.hint(.previousRatio)) ratio  ·  \(preferences.hint(.confirmCrop)) confirm  ·  \(preferences.hint(.cancelCrop)) cancel")
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
        defer { finishCropMode() }
        guard let current = appState.currentItem, let rect = cropSession.rect else { return }
        if current.isVirtualCopy {
            appState.cropRects[current.id] = rect
        } else if rect != .fullImage {
            let copy = appState.insertVirtualCopy(of: current, cropRect: rect)
            appState.jumpTo(copy)
        }
    }

    private func cancelCrop() {
        finishCropMode()
    }

    private func finishCropMode() {
        // Restore the window while the image is still pinned to its crop
        // size. Releasing the pin first lets it fill the screen-sized window
        // before the deferred isCropping subscriber restores the frame.
        exitCropWindowMode()
        appState.isCropping = false
    }

    // MARK: Keyboard

    private func dismissImageProperties() {
        imageProperties = nil
        propertiesFlashID = UUID()
    }

    private func handleKeyDown(_ event: NSEvent, appState: AppState) -> Bool {
        if handleCropKeyDown(event, appState: appState) {
            return true
        }
        if handleGlobalShortcuts(event, appState: appState) {
            return true
        }

        if preferences.matches(.submit, event) {
            appState.submit()
            return true
        }

        if preferences.matches(.previous, event) {
            appState.goToPrevious()
            return true
        }

        if preferences.matches(.next, event) {
            appState.goToNext()
            return true
        }

        guard let current = appState.currentItem else { return false }
        if preferences.matches(.info, event) {
            imageProperties = ImageProperties(item: current, cropRect: appState.cropRects[current.id])
            propertiesFlashID = UUID()
            return true
        }
        if preferences.matches(.pick, event) {
            appState.decide(current, .pick)
            return true
        }
        if preferences.matches(.reject, event) {
            appState.decide(current, .reject)
            return true
        }
        return false
    }

    /// Checked before every other key handler in culling, so an active crop
    /// swallows all input (Esc cancels the crop rather than triggering the
    /// quit-confirmation, arrows/j/k/p/x can't silently abandon it, etc.).
    private func handleCropKeyDown(_ event: NSEvent, appState: AppState) -> Bool {
        if !appState.isCropping {
            if preferences.matches(.crop, event) {
                enterCropMode()
                return true
            }
            return false
        }

        if preferences.matches(.confirmCrop, event) {
            commitCrop()
            return true
        }
        if preferences.matches(.cancelCrop, event) {
            cancelCrop()
            return true
        }
        if preferences.matches(.nextRatio, event) {
            cropSession.cycleAspectRatio(forward: true, presets: preferences.cropPresets)
            return true
        }
        if preferences.matches(.previousRatio, event) {
            cropSession.cycleAspectRatio(forward: false, presets: preferences.cropPresets)
            return true
        }
        if preferences.matches(.freeRatio, event) {
            cropSession.setAspectRatio(.free)
            return true
        }
        for action in ShortcutAction.allCases {
            if let index = action.presetIndex, preferences.matches(action, event) {
                if preferences.digitPresets.indices.contains(index) {
                    cropSession.setAspectRatio(preferences.digitPresets[index])
                }
                return true
            }
        }
        return true
    }
}
