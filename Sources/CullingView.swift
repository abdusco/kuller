import SwiftUI
import AppKit

struct CullingView: View {
    @ObservedObject var appState: AppState
    @State private var keyMonitor: KeyMonitor?

    var body: some View {
        ImageViewerView(item: appState.currentItem)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func handleKeyDown(_ event: NSEvent, appState: AppState) -> Bool {
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
}
