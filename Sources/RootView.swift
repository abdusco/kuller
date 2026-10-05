import SwiftUI

struct RootView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        content
            .onAppear { prefetch() }
            .onChange(of: appState.currentIndex) { _, _ in prefetch() }
            .onChange(of: appState.items) { _, _ in prefetch() }
            .onChange(of: appState.phase) { _, _ in prefetch() }
            .onDisappear { ThumbnailCache.shared.cancelPrefetching() }
    }

    @ViewBuilder
    private var content: some View {
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

    private func prefetch() {
        guard appState.phase == .culling else {
            ThumbnailCache.shared.cancelPrefetching()
            return
        }
        ThumbnailCache.shared.prefetch(items: appState.items, currentIndex: appState.currentIndex)
    }
}
