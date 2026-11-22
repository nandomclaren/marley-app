import Foundation

/// The device copy of the data, plus rotating local snapshots (an extra safety net on the phone itself).
public struct LocalStore: Sendable {
    public let directory: URL
    public static let keepBackups = 40

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: backupsDir, withIntermediateDirectories: true)
    }
    public static func appSupport() -> LocalStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return LocalStore(directory: base.appendingPathComponent("Marley", isDirectory: true))
    }

    public var dataFile: URL { directory.appendingPathComponent("marley-data.json") }
    public var backupsDir: URL { directory.appendingPathComponent("backups", isDirectory: true) }
    var stateFile: URL { directory.appendingPathComponent("sync-state.json") }

    public func load() -> AppData? {
        guard let s = try? String(contentsOf: dataFile, encoding: .utf8) else { return nil }
        return try? AppData.parse(s)
    }
    public func save(_ d: AppData) throws {
        try Data(d.serialized().utf8).write(to: dataFile, options: .atomic)
        let daily = backupsDir.appendingPathComponent("daily-\(Day.today()).json")
        if !FileManager.default.fileExists(atPath: daily.path) { try? Data(d.serialized().utf8).write(to: daily, options: .atomic); prune() }
    }
    /// Snapshot before something replaces the local data (adopting the server's version, a restore).
    public func snapshot(_ d: AppData, reason: String) {
        let stamp = Int(Date().timeIntervalSince1970)
        try? Data(d.serialized().utf8).write(to: backupsDir.appendingPathComponent("\(reason)-\(stamp).json"), options: .atomic)
        prune()
    }
    public func backups() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
    }
    func prune() { for u in backups().dropFirst(Self.keepBackups) { try? FileManager.default.removeItem(at: u) } }

    public func loadState() -> SyncState? {
        guard let d = try? Data(contentsOf: stateFile) else { return nil }
        return try? JSONDecoder().decode(SyncState.self, from: d)
    }
    public func saveState(_ s: SyncState) { try? JSONEncoder().encode(s).write(to: stateFile, options: .atomic) }
}
