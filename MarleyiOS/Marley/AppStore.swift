import SwiftUI
import UIKit
import MarleyCore

enum SyncStatus: Equatable {
    case unconfigured, idle, syncing, synced, error(String), blocked([String])
}

struct PendingQuestion: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirm: String
    let cancel: String
    let destructive: Bool
    let resume: (Bool) -> Void
}

/// App state. Every edit goes through `edit`, which saves to disk and schedules a push to the Gist.
@MainActor @Observable
final class AppStore {
    private(set) var data: AppData
    var selectedMonth: String
    var syncStatus: SyncStatus = .idle
    var pendingQuestion: PendingQuestion?
    var showSettings = false
    var launchedOnce = false

    @ObservationIgnored let local = LocalStore.appSupport()
    @ObservationIgnored private var syncState: SyncState
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private(set) var ai: AIChat!

    init() {
        let loaded = local.load()
        let d = loaded ?? AppData.emptyDocument()
        data = d
        syncState = local.loadState() ?? SyncState(lastSyncedTs: d.lastModified)
        let cm = String(Day.today().prefix(7))
        selectedMonth = d.months.contains(cm) ? cm : (d.months.last ?? cm)
        syncStatus = isConfigured ? .idle : .unconfigured
        let chatFile = local.directory.appendingPathComponent("ai-chat-v2.json")
        let saved = (try? String(contentsOf: chatFile, encoding: .utf8)).flatMap(AIConversation.fromJSON)
        ai = AIChat(streamer: KeychainAnthropicStreamer(), conversation: saved,
                    getData: { [unowned self] in self.data },
                    mutateData: { [unowned self] change in self.edit(change) })
        ai.persist = { conv in
            if let conv { try? Data(conv.toJSON().utf8).write(to: chatFile, options: .atomic) }
            else { try? FileManager.default.removeItem(at: chatFile) }
        }
    }

    var today: String { Day.today() }
    var hasData: Bool { !data.txns.isEmpty }

    // MARK: Settings

    var isConfigured: Bool { Keychain.get(Keychain.githubToken) != nil && Keychain.get(Keychain.gistId) != nil }
    var transport: GitHubGist? {
        guard let t = Keychain.get(Keychain.githubToken), let g = Keychain.get(Keychain.gistId) else { return nil }
        return GitHubGist(token: t, gistId: g)
    }
    var hasAIKey: Bool { Keychain.get(Keychain.anthropicKey) != nil }

    /// Saves the GitHub settings after checking they can read the Gist.
    func configure(token: String, gistId: String) async throws {
        let t = GitHubGist(token: token.trimmingCharacters(in: .whitespacesAndNewlines), gistId: gistId.trimmingCharacters(in: .whitespacesAndNewlines))
        _ = try await t.fetch()
        Keychain.set(Keychain.githubToken, t.token)
        Keychain.set(Keychain.gistId, t.gistId)
        await syncNow()
    }

    // MARK: Editing

    /// The only way data changes: apply, stamp, save locally, push a few seconds later.
    func edit(_ change: (inout AppData) -> Void) {
        var d = data
        change(&d)
        guard d != data else { return }
        d.lastModified = (Date().timeIntervalSince1970 * 1000).rounded()
        data = d
        persist()
        schedulePush()
    }
    private func persist() {
        do { try local.save(data) } catch { syncStatus = .error("Não consegui salvar no aparelho: \(error.localizedDescription)") }
    }

    func selectMonth(_ m: String) {
        selectedMonth = m
        guard canTouchData else { return }
        var d = data
        if Ledger.generateRecurring(&d, month: m) > 0 { edit { $0 = d } }
    }
    /// Never generate anything on top of data that wasn't checked against the server this session.
    /// (An empty first-launch document is never touched, so it can't look "newer" than the real data.)
    private var canTouchData: Bool { isConfigured ? syncState.hasSyncedThisSession : hasData }

    func addTransaction(date: String, desc: String, acct: String, amount: Double, isIncome: Bool, cat: String, notes: String,
                        recurring: Bool, uncertain: Bool, installments: Int) {
        edit { d in
            if installments > 1 {
                Installments.add(&d, total: amount, count: installments, date: date, desc: desc, acct: acct, isIncome: isIncome, cat: cat, notes: notes, uncertain: uncertain)
            } else {
                d.txns.append(Txn(id: d.nextId, date: date, desc: desc, acct: acct, out: isIncome ? 0 : amount, in_: isIncome ? amount : 0,
                                  notes: notes, cat: cat, recurring: recurring, warning: uncertain))
            }
        }
    }
    func updateTransaction(_ id: Int, date: String, desc: String, acct: String, amount: Double, isIncome: Bool, cat: String, notes: String,
                           recurring: Bool, uncertain: Bool) {
        edit { d in
            d.update(id) { t in
                t.date = date; t.desc = desc; t.acct = acct; t.cat = cat; t.notes = notes
                t.out = isIncome ? 0 : amount; t.in_ = isIncome ? amount : 0
                if !["opening", "salary", "critical"].contains(t.style) { t.style = "normal" }
                t.recurring = recurring; t.warning = uncertain
            }
        }
    }
    func delete(_ ids: Set<Int>) { edit { Ledger.delete(&$0, ids: ids) } }
    /// toggleCleared(): returns false when the transaction is in the future and needs a date first.
    @discardableResult
    func toggleCleared(_ id: Int) -> Bool {
        guard let t = data.txn(id), !t.locked else { return true }
        if !t.cleared && t.date > today { return false }
        edit { $0.update(id) { $0.cleared.toggle() } }
        return true
    }
    func clear(_ id: Int, on date: String) { edit { $0.update(id) { $0.date = date; $0.cleared = true } } }
    func setBudget(_ month: String, _ cat: String, _ value: Double) { edit { $0.setBudget(month, cat, value) } }
    func moveMoney(from: String, to: String, amount: Double) { edit { Ledger.moveMoney(&$0, month: selectedMonth, from: from, to: to, amount: amount) } }
    func reconcileConfirmed(_ acct: String) { edit { Ledger.lockCleared(&$0, acct) } }
    func reconcile(_ acct: String, bankBalance: Double) { edit { _ = Ledger.reconcileWithCorrection(&$0, acct, bankBalance: bankBalance, today: today) } }

    // MARK: Sync

    func syncNow() async {
        guard !syncing else { return }
        guard let transport else { syncStatus = .unconfigured; runMonthMaintenance(); return }
        syncing = true
        defer { syncing = false }
        pushTask?.cancel()
        syncStatus = .syncing
        let before = data
        var st = syncState
        do {
            let r = try await Sync.full(local: before, state: &st, transport: transport, ask: ask)
            if let nd = r.data {
                guard data == before else {
                    // edited while syncing: don't overwrite, try again
                    syncStatus = .error("Os dados mudaram durante a sincronização. Toque para tentar de novo.")
                    return
                }
                if r.outcome == .pulled { local.snapshot(before, reason: "antes-de-baixar") }
                data = nd
                persist()
            }
            syncState = st
            local.saveState(st)
            switch r.outcome {
            case .pulled, .pushed, .upToDate: syncStatus = .synced
            case .cancelled: syncStatus = .error("Sincronização cancelada. Nada foi alterado.")
            case .blocked(let issues): syncStatus = .blocked(issues)
            case .aborted(let m): syncStatus = .error(m)
            }
            if !data.months.contains(selectedMonth) { selectedMonth = data.months.last ?? selectedMonth }
            runMonthMaintenance()
        } catch {
            syncStatus = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Current month + 2 always exist; only after seeing the server this session.
    private func runMonthMaintenance() {
        guard canTouchData else { return }
        var d = data
        let added = Ledger.ensureMonthsAhead(&d, today: today)
        if !added.isEmpty { edit { $0 = d } }
        let cm = String(today.prefix(7))
        if !data.months.contains(selectedMonth) || (selectedMonth < cm && data.months.contains(cm) && !launchedOnce) { selectedMonth = cm }
        selectMonth(selectedMonth)
    }

    private func schedulePush() {
        guard transport != nil else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.autoPush()
        }
    }
    private func autoPush() async {
        guard let transport, !syncing else { return }
        var st = syncState
        let o = await Sync.autoPush(local: data, state: &st, transport: transport)
        syncState.lastSyncedTs = st.lastSyncedTs
        local.saveState(syncState)
        switch o {
        case .pushed: syncStatus = .synced
        case .upToDate: break
        case .blocked(let issues): syncStatus = .blocked(issues)
        case .aborted(let m): syncStatus = .error(m)
        default: break
        }
    }
    /// Going to the background: send pending changes now, with extra time from iOS.
    func flushPendingPush() {
        guard pushTask != nil, data.lastModified > syncState.lastSyncedTs else { return }
        pushTask?.cancel()
        let bg = UIApplication.shared.beginBackgroundTask(withName: "marley-push", expirationHandler: nil)
        Task {
            await autoPush()
            UIApplication.shared.endBackgroundTask(bg)
        }
    }

    /// "Restaurar do Gist": replace this device's data with the server's (a snapshot is kept on the device).
    func restoreFromGist() async {
        guard let transport else { return }
        var st = syncState
        do {
            let d = try await Sync.forcePull(state: &st, transport: transport)
            local.snapshot(data, reason: "antes-de-restaurar")
            data = d
            persist()
            syncState = st
            local.saveState(st)
            syncStatus = .synced
        } catch {
            syncStatus = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
    /// Restore a snapshot kept on the device. It becomes the newest version and syncs with the usual guards.
    func restoreLocalBackup(_ url: URL) {
        guard let s = try? String(contentsOf: url, encoding: .utf8), let d = try? AppData.parse(s) else { return }
        local.snapshot(data, reason: "antes-de-restaurar")
        edit { $0 = d }
    }
    func exportFile() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("marley-backup-\(today).json")
        try? Data(data.serialized().utf8).write(to: url, options: .atomic)
        return url
    }

    private func ask(_ q: SyncQuestion) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let fmt: (Double) -> String = { ts in
                ts > 0 ? Date(timeIntervalSince1970: ts / 1000).formatted(date: .abbreviated, time: .shortened) : "(desconhecido)"
            }
            var resumed = false
            let resume: (Bool) -> Void = { v in if !resumed { resumed = true; c.resume(returning: v) } }
            switch q {
            case .conflict(let l, let r):
                pendingQuestion = PendingQuestion(
                    title: "Conflito de dados",
                    message: "Este iPhone e outro aparelho mudaram os dados desde a última sincronização.\n\nNo iPhone: \(fmt(l))\nNo servidor: \(fmt(r))\n\nQual versão fica?",
                    confirm: "Manter a do iPhone", cancel: "Usar a do servidor", destructive: true, resume: resume)
            case .remoteHasFewerReconciled(let l, let r):
                pendingQuestion = PendingQuestion(
                    title: "Atenção",
                    message: "Os dados do servidor têm \(l - r) transação(ões) reconciliada(s) a menos que este iPhone. Adotar pode perder reconciliações.",
                    confirm: "Adotar mesmo assim", cancel: "Manter os do iPhone", destructive: true, resume: resume)
            case .pushLooksLikeDataLoss(let issues):
                pendingQuestion = PendingQuestion(
                    title: "Proteção de dados",
                    message: "Os dados deste iPhone parecem ter perdido coisas que estão no servidor:\n\n" + issues.map { "• \($0)" }.joined(separator: "\n") + "\n\nSe você não apagou isso de propósito, não envie.",
                    confirm: "Enviar mesmo assim", cancel: "Não enviar", destructive: true, resume: resume)
            }
        }
    }
}

extension AppData {
    /// First launch before the Gist is configured.
    static func emptyDocument() -> AppData {
        let m = String(Day.today().prefix(7))
        let rest = JSONObject([
            ("_lastModified", .number(0)),
            ("balances", .object(JSONObject([("rev", .number(0)), ("wise", .number(0)), ("swile", .number(0))]))),
            ("budgets", .object(JSONObject())), ("goals", .object(JSONObject())),
            ("txns", .array([])), ("months", .array([.string(m)])),
        ])
        return AppData(rest: rest, txns: [])
    }
}
