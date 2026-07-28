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
            HStack {
                Button("Back to Culling") {
                    appState.returnToCulling()
                }
                Spacer()
                if let feedback = lastCopyFeedback {
                    Text(feedback)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(10)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Picks (\(appState.picks.count))")
                        .font(.title3.bold())
                        .padding(12)
                    ImageGridView(coordinator: pickCoordinator, items: appState.picks)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    Text("Rejects (\(appState.rejects.count))")
                        .font(.title3.bold())
                        .padding(12)
                    ImageGridView(coordinator: rejectCoordinator, items: appState.rejects)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.16))
        .onAppear {
            configureCoordinators()
            keyMonitor = KeyMonitor { event in
                handleKeyDown(event)
            }
        }
        .onDisappear {
            keyMonitor?.stop()
            keyMonitor = nil
        }
    }

    private func configureCoordinators() {
        pickCoordinator.onSelectionChanged = { ids in
            pickSelection = ids
            focusedColumn = .picks
        }
        pickCoordinator.onDropReclassify = { ids in
            appState.setDecision(ids: ids, to: .pick)
        }
        rejectCoordinator.onSelectionChanged = { ids in
            rejectSelection = ids
            focusedColumn = .rejects
        }
        rejectCoordinator.onDropReclassify = { ids in
            appState.setDecision(ids: ids, to: .reject)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if handleGlobalShortcuts(event, appState: appState) {
            return true
        }

        guard event.modifierFlags.contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

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

    private func copySelection() {
        let urls: [URL]
        switch focusedColumn {
        case .picks:
            urls = appState.picks.filter { pickSelection.contains($0.id) }.map { $0.url }
        case .rejects:
            urls = appState.rejects.filter { rejectSelection.contains($0.id) }.map { $0.url }
        case nil:
            urls = []
        }
        guard !urls.isEmpty else { return }
        FilePasteboard.copy(urls: urls)
        lastCopyFeedback = "Copied \(urls.count) file\(urls.count == 1 ? "" : "s")"
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
