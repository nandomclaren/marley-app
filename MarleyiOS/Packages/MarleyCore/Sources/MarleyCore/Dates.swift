import Foundation

/// Dates are plain "yyyy-MM-dd" strings and months "yyyy-MM", exactly like the stored data.
public enum Day {
    public static func today(_ now: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func parts(_ d: String) -> (y: Int, m: Int, d: Int) {
        let p = d.split(separator: "-").compactMap { Int($0) }
        return (p.count > 0 ? p[0] : 0, p.count > 1 ? p[1] : 1, p.count > 2 ? p[2] : 1)
    }
    public static func month(_ y: Int, _ m: Int) -> String { String(format: "%04d-%02d", y, m) }
    public static func nextMonth(_ m: String) -> String { let p = parts(m); return p.m == 12 ? month(p.y + 1, 1) : month(p.y, p.m + 1) }
    public static func prevMonth(_ m: String) -> String { let p = parts(m); return p.m == 1 ? month(p.y - 1, 12) : month(p.y, p.m - 1) }
    public static func lastDay(_ m: String) -> Int {
        let p = parts(m)
        switch p.m {
        case 2: return (p.y % 4 == 0 && p.y % 100 != 0) || p.y % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
    /// Same date k months later, day clamped to the month's end (addMonthsToDate in the web app).
    public static func addMonths(_ date: String, _ k: Int) -> String {
        let p = parts(date)
        let tot = p.y * 12 + (p.m - 1) + k
        let ym = month(tot / 12, tot % 12 + 1)
        return String(format: "%@-%02d", ym, min(p.d, lastDay(ym)))
    }
    public static let monthNames = ["Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho", "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"]
    public static func monthName(_ m: String) -> String { monthNames[max(0, min(11, parts(m).m - 1))] }
    public static func monthLabel(_ m: String, withYear: Bool = false) -> String {
        withYear ? "\(monthName(m)) \(parts(m).y)" : monthName(m)
    }
    /// "dd/MM"
    public static func short(_ d: String) -> String { let p = parts(d); return String(format: "%02d/%02d", p.d, p.m) }
    public static func date(_ d: String) -> Date? {
        let p = parts(d)
        var c = DateComponents(); c.year = p.y; c.month = p.m; c.day = p.d; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)
    }
    public static func string(_ date: Date, calendar: Calendar = .current) -> String { today(date, calendar: calendar) }
    public static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let x = date(a), let y = date(b) else { return 0 }
        return Int(((y.timeIntervalSince(x)) / 86400).rounded())
    }
}
