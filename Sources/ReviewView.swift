import SwiftUI
import AppKit

struct ReviewView: View {
    @ObservedObject var appState: AppState

    @State private var pickCoordinator = ImageGridCoordinator(kind: .picks)
    @State private var rejectCoordinator = ImageGridCoordinator(kind: .rejects)
    @State private var pickSelection: Set<UUID> = []
    @State private var rejectSelection: Set<UUID> = []
    @State private var focusedColumn: ReviewColumnKind?
    @State private var keyMonitor: KeyMonitor?
    @State private var lastCopyFeedback: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            HStack(spacing: 0) {
                column(
                    title: "Picks",
                    icon: "checkmark.circle.fill",
                    tint: .green,
                    items: appState.picks,
                    coordinator: pickCoordinator,
                    emptyMessage: "Nothing picked"
                )

                hairline

                column(
                    title: "Rejects",
                    icon: "xmark.circle.fill",
                    tint: .red,
                    items: appState.rejects,
                    coordinator: rejectCoordinator,
                    emptyMessage: "Nothing rejected"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Blur the desktop behind the window, then sit the dark tint on
            // top of it so thumbnails read against a stable backdrop instead
            // of whatever happens to be on screen.
            VisualEffectBackground()
                .overlay(Color.black.opacity(0.8))
        }
        .onAppear {
            configureCoordinators()
            keyMonitor = KeyMonitor { event in
                handleKeyDown(event)
            }
        }
        .onDisappear {
            keyMonitor?.stop()
            keyMonitor = nil
            QuickLookController.shared.close()
        }
    }

    // MARK: Chrome

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                appState.returnToCulling()
            } label: {
                Label("Back to Culling", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.accessoryBar)

            Spacer(minLength: 12)

            if let feedback = lastCopyFeedback {
                Label(feedback, systemImage: "doc.on.doc.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            Text(Self.shortcutHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .overlay(alignment: .bottom) { hairline.frame(maxWidth: .infinity, maxHeight: 1) }
        .animation(.easeInOut(duration: 0.15), value: lastCopyFeedback)
    }

    private static let shortcutHint = "P / X move  ·  Space previews  ·  ⌘C copies"

    private var hairline: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1)
    }

    /// One review column: a header with an icon, name and count pill, then
    /// the grid (or a placeholder while the column is empty).
    private func column(
        title: String,
        icon: String,
        tint: Color,
        items: [ImageItem],
        coordinator: ImageGridCoordinator,
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(items.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            ImageGridView(coordinator: coordinator, items: items, cropRects: appState.cropRects)
                .overlay {
                    if items.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 26, weight: .light))
                            Text(emptyMessage)
                                .font(.callout)
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Wiring

    private func configureCoordinators() {
        pickCoordinator.onSelectionChanged = { ids in
            pickSelection = ids
            focusedColumn = .picks
        }
        pickCoordinator.onDropReclassify = { ids in
            appState.setDecision(ids: ids, to: .pick)
        }
        pickCoordinator.onDeleteVirtualCopy = { item in
            appState.removeVirtualCopy(item)
        }
        rejectCoordinator.onSelectionChanged = { ids in
            rejectSelection = ids
            focusedColumn = .rejects
        }
        rejectCoordinator.onDropReclassify = { ids in
            appState.setDecision(ids: ids, to: .reject)
        }
        rejectCoordinator.onDeleteVirtualCopy = { item in
            appState.removeVirtualCopy(item)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if handleGlobalShortcuts(event, appState: appState) {
            return true
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        if event.modifierFlags.contains(.command) {
            switch characters {
            case "c":
                copySelection()
                return true
            case "a":
                selectAllInFocusedColumn()
                return true
            default:
                return false
            }
        }

        switch characters {
        case "p":
            moveSelection(to: .pick)
            return true
        case "x":
            moveSelection(to: .reject)
            return true
        case " ":
            previewSelection()
            return true
        default:
            return false
        }
    }

    /// Quick Look, matching Finder: previewing a single image lets the arrow
    /// keys walk the whole column from there, while previewing a multi-image
    /// selection stays within that selection.
    private func previewSelection() {
        let selected = selectedItems()
        guard !selected.isEmpty else { return }

        if selected.count == 1, let index = columnItems().firstIndex(of: selected[0]) {
            QuickLookController.shared.toggle(items: columnItems(), cropRects: appState.cropRects, startIndex: index)
        } else {
            QuickLookController.shared.toggle(items: selected, cropRects: appState.cropRects)
        }
    }

    /// Every item in whichever column was last interacted with, in display
    /// order.
    private func columnItems() -> [ImageItem] {
        switch focusedColumn {
        case .picks:
            return appState.picks
        case .rejects:
            return appState.rejects
        case nil:
            return []
        }
    }

    /// The currently-selected items in whichever column was last interacted
    /// with.
    private func selectedItems() -> [ImageItem] {
        switch focusedColumn {
        case .picks:
            return appState.picks.filter { pickSelection.contains($0.id) }
        case .rejects:
            return appState.rejects.filter { rejectSelection.contains($0.id) }
        case nil:
            return []
        }
    }

    /// Moves the currently-selected images (in whichever column was last
    /// interacted with) to the other group, like dragging them across.
    private func moveSelection(to decision: Decision) {
        let ids: [UUID]
        switch focusedColumn {
        case .picks:
            ids = Array(pickSelection)
        case .rejects:
            ids = Array(rejectSelection)
        case nil:
            ids = []
        }
        guard !ids.isEmpty else { return }
        appState.setDecision(ids: ids, to: decision)
        switch focusedColumn {
        case .picks:
            pickSelection = []
        case .rejects:
            rejectSelection = []
        case nil:
            break
        }
    }

    private func copySelection() {
        let items = selectedItems()
        guard !items.isEmpty else { return }
        resolveURLs(for: items) { urls in
            FilePasteboard.copy(urls: urls)
            lastCopyFeedback = "Copied \(urls.count) file\(urls.count == 1 ? "" : "s")"
        }
    }

    /// Resolves each item to the file that should actually represent it —
    /// its committed crop rendered to a temp file, if any, otherwise the
    /// original — before handing URLs to the pasteboard.
    private func resolveURLs(for items: [ImageItem], completion: @escaping ([URL]) -> Void) {
        var resolved = [URL?](repeating: nil, count: items.count)
        let group = DispatchGroup()
        for (index, item) in items.enumerated() {
            group.enter()
            CroppedImageRenderer.resolvedURL(for: item, cropRects: appState.cropRects) { url in
                resolved[index] = url
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(resolved.compactMap { $0 })
        }
    }

    private func selectAllInFocusedColumn() {
        switch focusedColumn {
        case .picks:
            pickCoordinator.collectionView?.selectAll(nil)
        case .rejects:
            rejectCoordinator.collectionView?.selectAll(nil)
        case nil:
            break
        }
    }
}
