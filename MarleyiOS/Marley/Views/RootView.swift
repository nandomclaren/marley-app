import SwiftUI
import MarleyCore

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView {
            Tab("Fluxo", systemImage: "list.bullet.rectangle.portrait") { FluxoView() }
            Tab("Contas", systemImage: "building.columns") { ContasView() }
            Tab("Budget", systemImage: "chart.pie") { BudgetView() }
            Tab("Reflect", systemImage: "sparkles") { ReflectView() }
            Tab("IA", systemImage: "bubble.left.and.text.bubble.right") { AIView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $store.showSettings) { SettingsView() }
        .alert(store.pendingQuestion?.title ?? "", isPresented: Binding(get: { store.pendingQuestion != nil }, set: { _ in }), presenting: store.pendingQuestion) { q in
            Button(q.confirm, role: q.destructive ? .destructive : nil) { store.pendingQuestion = nil; q.resume(true) }
            Button(q.cancel, role: .cancel) { store.pendingQuestion = nil; q.resume(false) }
        } message: { q in Text(q.message) }
        .overlay {
            if !store.hasData && store.syncStatus == .unconfigured {
                ContentUnavailableView {
                    Label("Bem-vindo ao Marley", systemImage: "pawprint.fill")
                } description: {
                    Text("Conecte o Gist do GitHub para carregar os seus dados.")
                } actions: {
                    Button("Configurar") { store.showSettings = true }.buttonStyle(.glassProminent)
                }
                .background(.background)
            }
        }
    }
}
