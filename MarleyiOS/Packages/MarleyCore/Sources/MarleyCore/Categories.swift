import Foundation

public struct CategoryGroup: Sendable, Hashable {
    public let group: String
    public let cats: [String]
}

/// Same list, in the same order, as CATEGORIES in the web app.
public enum Categories {
    public static let groups: [CategoryGroup] = [
        .init(group: "Personal Budgets", cats: ["💁🏻‍♂️ Nando", "💁🏼‍♀️ Thati"]),
        .init(group: "Alimentation", cats: ["🍕 Uber Eats & Restos", "🛒 Courses & Marché", "🥐 Boulangerie"]),
        .init(group: "Dépenses fixes", cats: ["💸 Bail", "🎒 Open Sky", "🏫 École Thiers", "💡 Électricité", "📱 Forfaits Mobile", "💻 Abonnements", "🙏 Dons"]),
        .init(group: "Mobilité", cats: ["🚇 RATP", "🚖 Uber"]),
        .init(group: "Santé", cats: ["🩺 Médecins & Pharmacie", "💈 Auto soin"]),
        .init(group: "Maison", cats: ["🪛 Entretien & Fournitures", "🏦 Frais & Admin"]),
        .init(group: "Enfants", cats: ["👭 Sá & Sô", "🧣 Vêtements"]),
        .init(group: "Qualité de Vie", cats: ["🧑‍🧑‍🧒‍🧒 Sortie Famille", "👩🏼‍❤️‍💋‍👨🏻 Dates", "🥳 Fêtes & Cadeaux"]),
        .init(group: "Prévoyance", cats: ["🏝️ Vacances", "🛋️ Équipement Maison", "💼 Voyage Travail", "🔄 Transfert de Devises"]),
    ]
    public static let all: [String] = groups.flatMap(\.cats)

    /// Leading emoji of a category ("🛒 Courses & Marché" -> "🛒").
    public static func emoji(_ cat: String) -> String {
        guard let sp = cat.firstIndex(of: " ") else { return "" }
        return String(cat[..<sp])
    }
    public static func name(_ cat: String) -> String {
        guard let sp = cat.firstIndex(of: " ") else { return cat }
        return String(cat[cat.index(after: sp)...])
    }
    public static func groupIndex(of cat: String) -> Int? { groups.firstIndex { $0.cats.contains(cat) } }
}

/// Strips the leading emoji/symbols of a description for display (dispDesc in the web app).
public func displayDescription(_ s: String) -> String {
    let scalars = s.unicodeScalars
    guard let first = scalars.firstIndex(where: { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }) else { return s.trimmingCharacters(in: .whitespaces) }
    return String(String.UnicodeScalarView(scalars[first...])).trimmingCharacters(in: .whitespaces)
}
