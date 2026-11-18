import Foundation

/// One entry in the command palette: a page, a meeting, a mode, or
/// an action. The palette is the reel's lesson applied to a native
/// app (jump anywhere, run anything, one keyboard box), and the
/// ranking lives here so it is testable without a window: the app
/// builds the items from its live state, the filter decides what a
/// query shows and in which order.
public struct PaletteItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    /// The section the item sits in when the palette opens empty:
    /// "Go to", "Actions", "Modes", "Meetings", "Meeting".
    public var group: String
    /// Extra words a query can hit that the title does not carry:
    /// synonyms, the words of a meeting's title, a mode's purpose.
    public var keywords: String

    public init(id: String, title: String, subtitle: String, group: String, keywords: String = "") {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.group = group
        self.keywords = keywords
    }
}

/// Ranking a palette query against the items. A title that starts
/// with the query beats a word inside the title that starts with
/// it, which beats a plain containment, which beats a keyword hit,
/// which beats a subsequence (the letters in order, gaps allowed).
/// Anything else is not a match. Ties keep the order the app
/// supplied, so the curated order survives inside a tier.
public enum PaletteFilter {
    public static func ranked(_ items: [PaletteItem], query: String) -> [PaletteItem] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return items }
        var scored: [(tier: Int, index: Int, item: PaletteItem)] = []
        for (index, item) in items.enumerated() {
            guard let tier = tier(of: item, needle: needle) else { continue }
            scored.append((tier, index, item))
        }
        return scored
            .sorted { $0.tier != $1.tier ? $0.tier < $1.tier : $0.index < $1.index }
            .map(\.item)
    }

    private static func tier(of item: PaletteItem, needle: String) -> Int? {
        let title = normalize(item.title)
        if title.hasPrefix(needle) { return 0 }
        if title.components(separatedBy: " ").contains(where: { $0.hasPrefix(needle) }) { return 1 }
        if title.contains(needle) { return 2 }
        if normalize(item.keywords).contains(needle) { return 3 }
        if isSubsequence(needle, of: title) { return 4 }
        return nil
    }

    /// Lowercased, single-spaced: the shape titles and queries are
    /// compared in, so casing and stray spaces never break a match.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func isSubsequence(_ needle: String, of text: String) -> Bool {
        var rest = text[...]
        for character in needle {
            guard let found = rest.firstIndex(of: character) else { return false }
            rest = rest[rest.index(after: found)...]
        }
        return true
    }
}
