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
    public var hasSyncedThisSession: Bool = false
    public init(lastSyncedTs: Double) { self.lastSyncedTs = lastSyncedTs }
    enum CodingKeys: String, CodingKey { case lastSyncedTs }
}

public enum Sync {
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
            let localChanged = localTs > state.lastSyncedTs
            let remoteChanged = remoteTs > state.lastSyncedTs
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
            return .aborted("Outro aparelho alterou os dados. Toque em sincronizar para resolver.")
        }
        let issues = SyncGuards.pushIssues(local: local, remote: remote)
        if !issues.isEmpty { return .blocked(issues) }
        do { try await transport.push(local.serialized()) }
        catch { return .aborted("Falha ao enviar: \(error.localizedDescription)") }
        state.lastSyncedTs = local.lastModified
        return .pushed
    }

    /// "Restaurar do Gist": take the server's version as is.
    public static func forcePull(state: inout SyncState, transport: GistTransport) async throws -> AppData {
        guard let content = try await transport.fetch() else { throw SyncError.noRemoteFile }
        var d = try AppData.parse(content)
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
