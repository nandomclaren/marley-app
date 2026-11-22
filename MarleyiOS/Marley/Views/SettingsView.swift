import SwiftUI
import MarleyCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var token = Keychain.get(Keychain.githubToken) ?? ""
    @State private var gistId = Keychain.get(Keychain.gistId) ?? ""
    @State private var aiKey = Keychain.get(Keychain.anthropicKey) ?? ""
    @State private var testing = false
    @State private var githubMessage: String?
    @State private var aiSaved = false
    @State private var confirmRestore = false
    @State private var restoringBackup: URL?
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Personal Access Token", text: $token).textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("Gist ID", text: $gistId).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button {
                        testing = true; githubMessage = nil
                        Task {
                            do { try await store.configure(token: token, gistId: gistId); githubMessage = "✅ Conectado." }
                            catch { githubMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
                            testing = false
                        }
                    } label: { HStack { Text("Testar e salvar"); if testing { Spacer(); ProgressView() } } }
                    .disabled(token.isEmpty || gistId.isEmpty || testing)
                } header: { Text("Sincronização (GitHub Gist)") } footer: {
                    Text(githubMessage ?? "O mesmo token (scope gist) e Gist ID do Marley web. Ficam no Keychain do iPhone.")
                }

                Section {
                    LabeledContent("Estado", value: statusText)
                    Button("Sincronizar agora") { Task { await store.syncNow() } }.disabled(!store.isConfigured)
                }

                Section {
                    SecureField("sk-ant-…", text: $aiKey).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button(aiSaved ? "Salva ✓" : "Salvar chave") { Keychain.set(Keychain.anthropicKey, aiKey.trimmingCharacters(in: .whitespacesAndNewlines)); aiSaved = true }
                } header: { Text("Consultor (IA)") } footer: {
                    Text("Chave da API Anthropic (console.anthropic.com → API Keys). Fica só no Keychain deste iPhone.")
                }

                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Exportar backup (JSON)", systemImage: "square.and.arrow.up") }
                    } else {
                        Button { exportURL = store.exportFile() } label: { Label("Preparar backup (JSON)", systemImage: "square.and.arrow.up") }
                    }
                    Button(role: .destructive) { confirmRestore = true } label: { Label("Restaurar do Gist", systemImage: "arrow.down.circle") }
                        .disabled(!store.isConfigured)
                    NavigationLink { LocalBackupsView(restoring: $restoringBackup) } label: { Label("Backups neste iPhone", systemImage: "clock.arrow.circlepath") }
                } header: { Text("Backup") } footer: {
                    Text("Além do histórico de hora em hora no GitHub, o iPhone guarda uma cópia por dia e uma antes de cada substituição dos dados.")
                }

                Section {
                    LabeledContent("Transações", value: "\(store.data.txns.count)")
                    LabeledContent("Reconciliadas", value: "\(store.data.lockedCount)")
                    LabeledContent("Versão", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .keyboardDismissable()
            .onAppear { exportURL = store.exportFile() }
            .navigationTitle("Configurações")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .confirmationDialog("Substituir os dados deste iPhone pelos do Gist?", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Restaurar do Gist", role: .destructive) { Task { await store.restoreFromGist() } }
            } message: { Text("Uma cópia dos dados atuais fica guardada em Backups neste iPhone.") }
            .confirmationDialog("Restaurar este backup?", isPresented: Binding(get: { restoringBackup != nil }, set: { if !$0 { restoringBackup = nil } }), titleVisibility: .visible, presenting: restoringBackup) { url in
                Button("Restaurar", role: .destructive) { store.restoreLocalBackup(url); restoringBackup = nil }
            } message: { _ in Text("Ele passa a ser a versão mais recente e é enviado ao Gist (com as proteções de sempre). Os dados atuais ficam guardados antes.") }
        }
    }

    var statusText: String {
        switch store.syncStatus {
        case .unconfigured: return "Não configurado"
        case .idle: return "—"
        case .syncing: return "Sincronizando…"
        case .synced: return "Sincronizado"
        case .error: return "Erro"
        case .blocked: return "Envio bloqueado"
        }
    }
}

struct LocalBackupsView: View {
    @Environment(AppStore.self) private var store
    @Binding var restoring: URL?
    var body: some View {
        let files = store.local.backups()
        List {
            ForEach(files, id: \.self) { url in
                let d = (try? String(contentsOf: url, encoding: .utf8)).flatMap { try? AppData.parse($0) }
                Button { restoring = url } label: {
                    VStack(alignment: .leading) {
                        Text(url.deletingPathExtension().lastPathComponent)
                        Text(d.map { "\($0.txns.count) transações · \($0.lockedCount) reconciliadas" } ?? "arquivo ilegível").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(d == nil)
            }
            if files.isEmpty { Text("Nenhum backup ainda.").foregroundStyle(.secondary) }
        }
        .navigationTitle("Backups neste iPhone")
    }
}
