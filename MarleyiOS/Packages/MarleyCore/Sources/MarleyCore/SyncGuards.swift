import Foundation

/// pushGuardIssues(): reasons to refuse overwriting the server with local data that looks like it lost things.
public enum SyncGuards {
    public static let tolerance = 5
    public static func pushIssues(local: AppData, remote: AppData?) -> [String] {
        guard let remote else { return [] }
        var issues: [String] = []
        let l = local.txns.count, r = remote.txns.count
        if l < r - tolerance { issues.append("\(r - l) transações a menos que o servidor (\(l) vs \(r))") }
        let ll = local.lockedCount, rl = remote.lockedCount
        if ll < rl - tolerance { issues.append("\(rl - ll) transações reconciliadas a menos (\(ll) vs \(rl))") }
        let ls = local.serialized().utf8.count, rs = remote.serialized().utf8.count
        if rs > 0 && Double(ls) < Double(rs) * 0.7 { issues.append("tamanho \(Int((Double(ls) / Double(rs) * 100).rounded()))% do que está no servidor") }
        return issues
    }
}
