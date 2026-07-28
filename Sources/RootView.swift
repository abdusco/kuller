import SwiftUI

struct RootView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        switch appState.phase {
        case .culling:
            // The image fills the window edge to edge, including the area
            // behind the transparent title bar.
            CullingView(appState: appState)
                .ignoresSafeArea()
        case .review:
            // Review keeps a normal title bar with its content below it.
            ReviewView(appState: appState)
        }
    }
}
