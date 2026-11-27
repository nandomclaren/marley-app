import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where marley-data.json lives (the Gist). Abstracted so the sync rules can be tested.
public protocol GistTransport: Sendable {
    /// Content of marley-data.json, or nil when the file doesn't exist yet.
    func fetch() async throws -> String?
    func push(_ content: String) async throws
}

/// Questions only the user can answer. `true` always means "go ahead with the risky option".
public enum SyncQuestion: Equatable, Sendable {
    /// The server has fewer reconciled transactions than this device. true = adopt the server anyway.
    case remoteHasFewerReconciled(local: Int, remote: Int)
    /// Both this device and another one changed the data since the last sync. true = keep this device's version.
    case conflict(localTs: Double, remoteTs: Double)
    /// This device's data looks like it lost things the server has. true = overwrite the server anyway.
    case pushLooksLikeDataLoss([String])
}

public enum SyncOutcome: Equatable, Sendable {
    case pulled            // adopted the server's newer data
    case pushed            // sent this device's data
    case upToDate
    case cancelled         // the user chose not to proceed; nothing changed
    case blocked([String]) // push refused by the data-loss guard
    case aborted(String)   // auto-push skipped (another device wrote, or network)
}

/// Sync bookkeeping. `lastSyncedTs` is persisted so a conflict is detected even across app launches.
public struct SyncState: Codable, Equatable, Sendable {
    public var lastSyncedTs: Double
    /// Impressões digitais das versões que ESTE aparelho enviou ou adotou (as mais recentes no fim).
    /// Se o servidor tem uma delas, a mudança veio daqui (por exemplo, um envio cuja resposta se perdeu), não de outro aparelho.
    public var knownHashes: [String] = []
    public var hasSyncedThisSession: Bool = false
    public init(lastSyncedTs: Double) { self.lastSyncedTs = lastSyncedTs }
    enum CodingKeys: String, CodingKey { case lastSyncedTs, knownHashes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastSyncedTs = try c.decode(Double.self, forKey: .lastSyncedTs)
        knownHashes = try c.decodeIfPresent([String].self, forKey: .knownHashes) ?? []
    }
    public mutating func remember(_ d: AppData) {
        let h = Sync.fingerprint(d)
        knownHashes.removeAll { $0 == h }
        knownHashes.append(h)
        if knownHashes.count > 10 { knownHashes.removeFirst(knownHashes.count - 10) }
    }
    public func isOurs(_ d: AppData) -> Bool { knownHashes.contains(Sync.fingerprint(d)) }
}

public enum Sync {
    /// Impressão digital estável do conteúdo (FNV-1a 64 bits sobre o JSON serializado, que é determinístico).
    public static func fingerprint(_ d: AppData) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in d.serialized().utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    public struct Result: Sendable {
        public let outcome: SyncOutcome
        /// New local data when it changed (adopted from the server, or re-stamped to win a conflict).
        public let data: AppData?
    }

    /// Manual / launch / foreground sync: pull if the server is newer, push if this device is newer,
    /// ask when both changed, and never push something that looks like data loss without asking.
    public static func full(local: AppData, state: inout SyncState, transport: GistTransport,
                            now: Double = Date().timeIntervalSince1970 * 1000,
                            ask: (SyncQuestion) async -> Bool) async throws -> Result {
        let content = try await transport.fetch()
        let remote: AppData? = content.flatMap { try? AppData.parse($0) }
        var toPush = local
        if let remote {
            let localTs = local.lastModified, remoteTs = remote.lastModified
            // o servidor tem uma versão que este aparelho mesmo produziu: não é mudança de outro aparelho
            let remoteIsOurs = state.isOurs(remote)
            if remoteIsOurs && remoteTs > state.lastSyncedTs { state.lastSyncedTs = remoteTs }
            let localChanged = localTs > state.lastSyncedTs
            let remoteChanged = remoteTs > state.lastSyncedTs && !remoteIsOurs
            if remoteTs == localTs {
                state.lastSyncedTs = localTs
                state.hasSyncedThisSession = true
                return Result(outcome: .upToDate, data: nil)
            }
            if remoteChanged && localChanged {
                if await ask(.conflict(localTs: localTs, remoteTs: remoteTs)) {
                    toPush.lastModified = max(now, remoteTs + 1) // make sure this version wins everywhere
                } else {
                    return await adopt(remote, local: local, state: &state, ask: ask)
                }
            } else if remoteTs > localTs {
                return await adopt(remote, local: local, state: &state, ask: ask)
            }
        }
        let issues = SyncGuards.pushIssues(local: toPush, remote: remote)
        if !issues.isEmpty, !(await ask(.pushLooksLikeDataLoss(issues))) {
            return Result(outcome: .blocked(issues), data: toPush == local ? nil : toPush)
        }
        state.remember(toPush) // antes de enviar: se a resposta se perder, a versão continua reconhecida como nossa
        try await transport.push(toPush.serialized())
        state.lastSyncedTs = toPush.lastModified
        state.hasSyncedThisSession = true
        return Result(outcome: .pushed, data: toPush == local ? nil : toPush)
    }

    static func adopt(_ remote: AppData, local: AppData, state: inout SyncState, ask: (SyncQuestion) async -> Bool) async -> Result {
        if remote.lockedCount < local.lockedCount,
           !(await ask(.remoteHasFewerReconciled(local: local.lockedCount, remote: remote.lockedCount))) {
            return Result(outcome: .cancelled, data: nil)
        }
        var d = remote
        Ledger.resetFutureLocks(&d, today: Day.today())
        state.remember(remote)
        state.lastSyncedTs = remote.lastModified
        state.hasSyncedThisSession = true
        return Result(outcome: .pulled, data: d)
    }

    /// Background push after an edit. Only after a sync this session, and only if nobody else wrote in between.
    public static func autoPush(local: AppData, state: inout SyncState, transport: GistTransport) async -> SyncOutcome {
        guard state.hasSyncedThisSession, local.lastModified > state.lastSyncedTs else { return .upToDate }
        let remote: AppData?
        do { remote = try await transport.fetch().flatMap { try? AppData.parse($0) } }
        catch { return .aborted("Sem conexão com o GitHub: \(error.localizedDescription)") }
        if let remote, remote.lastModified > state.lastSyncedTs {
            guard state.isOurs(remote) else { return .aborted("Outro aparelho alterou os dados. Toque em sincronizar para resolver.") }
            state.lastSyncedTs = remote.lastModified // um envio nosso anterior que não ficou registrado
            guard local.lastModified > state.lastSyncedTs else { return .upToDate }
        }
        let issues = SyncGuards.pushIssues(local: local, remote: remote)
        if !issues.isEmpty { return .blocked(issues) }
        state.remember(local)
        do { try await transport.push(local.serialized()) }
        catch { return .aborted("Falha ao enviar: \(error.localizedDescription)") }
        state.lastSyncedTs = local.lastModified
        return .pushed
    }

    /// "Restaurar do Gist": take the server's version as is.
    public static func forcePull(state: inout SyncState, transport: GistTransport) async throws -> AppData {
        guard let content = try await transport.fetch() else { throw SyncError.noRemoteFile }
        var d = try AppData.parse(content)
        state.remember(d)
        Ledger.resetFutureLocks(&d, today: Day.today())
        state.lastSyncedTs = d.lastModified
        state.hasSyncedThisSession = true
        return d
    }
}

public enum SyncError: Error, LocalizedError, Equatable {
    case noRemoteFile
    case http(Int, String)
    case badResponse
    public var errorDescription: String? {
        switch self {
        case .noRemoteFile: return "O Gist não tem o arquivo marley-data.json."
        case .http(let code, let msg): return code == 401 ? "Token do GitHub inválido (401)." : code == 404 ? "Gist não encontrado (404)." : "GitHub respondeu \(code): \(msg)"
        case .badResponse: return "Resposta inesperada do GitHub."
        }
    }
}

/// The real Gist, through the GitHub API.
public struct GitHubGist: GistTransport {
    public let token: String
    public let gistId: String
    public static let fileName = "marley-data.json"
    public init(token: String, gistId: String) { self.token = token; self.gistId = gistId }

    var url: URL { URL(string: "https://api.github.com/gists/\(gistId)")! }

    func request(_ url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if let body { r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        r.timeoutInterval = 60
        return r
    }
    static func check(_ data: Data, _ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { throw SyncError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw SyncError.http(http.statusCode, String(decoding: data.prefix(200), as: UTF8.self)) }
    }

    public func fetch() async throws -> String? {
        let (data, resp) = try await URLSession.shared.data(for: request(url))
        try Self.check(data, resp)
        guard case .object(let gist) = try JSON.parse(data), let files = gist["files"]?.objectValue else { throw SyncError.badResponse }
        guard let file = files[Self.fileName]?.objectValue else { return nil }
        if let content = file["content"]?.stringValue, file["truncated"]?.boolValue != true { return content }
        // Large files come truncated in the API response; raw_url always has the full content.
        guard let raw = file["raw_url"]?.stringValue, let rawURL = URL(string: raw) else { throw SyncError.badResponse }
        let (rd, rr) = try await URLSession.shared.data(for: request(rawURL))
        try Self.check(rd, rr)
        return String(decoding: rd, as: UTF8.self)
    }

    public func push(_ content: String) async throws {
        let body = JSON.serialize(.object(JSONObject([("files", .object(JSONObject([(Self.fileName, .object(JSONObject([("content", .string(content))])))])))])))
        let (data, resp) = try await URLSession.shared.data(for: request(url, method: "PATCH", body: Data(body.utf8)))
        try Self.check(data, resp)
    }
}
