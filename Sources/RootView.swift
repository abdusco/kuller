import SwiftUI

struct RootView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            switch appState.phase {
            case .culling:
                CullingView(appState: appState)
            case .review:
                ReviewView(appState: appState)
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .ignoresSafeArea()
    }
}
