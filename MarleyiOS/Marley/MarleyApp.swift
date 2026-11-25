import SwiftUI
import MarleyCore

@main
struct MarleyApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(.marleyAccent)
                .task { await store.syncNow() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.refreshDay()
                if store.launchedOnce { Task { await store.syncNow() } }
            case .background: store.flushPendingPush()
            default: break
            }
            if phase == .active { store.launchedOnce = true }
        }
    }
}
