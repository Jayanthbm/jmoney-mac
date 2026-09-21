import Foundation

/// The search-and-sort behaviour the four management screens share.
///
/// `filterAndSortCategories`, `filterAndSortPayees` and `filterAndSortGroups`
/// are the same function three times over: an optional case-insensitive substring
/// search, then either the fixed `priority ASC` order that reorder mode requires
/// or the user's chosen `name`/`priority` order in either direction. Quick
/// transactions use the same search with a priority-only order (that screen has no
/// sort menu). One implementation, so the three screens cannot drift apart.
enum EntityOrdering {
    /// The sort menu's two modes. The labels mirror `CategorySortModal` /
    /// `PayeeSortModal` / the groups sheet.
    enum SortKey: String, CaseIterable, Identifiable {
        case name
        case priority

        var id: String { rawValue }

        var title: String {
            switch self {
            case .name: return "Name"
            case .priority: return "Priority"
            }
        }
    }

    // MARK: - Search

    /// The source's search gate and comparison, quirks included.
    ///
    /// The *gate* is `searchQuery.trim()` (an all-whitespace query searches
    /// nothing) but the *needle* is `searchQuery.toLowerCase()` **untrimmed**, so
    /// a trailing space in the query matches nothing at all. Preserved: it is the
    /// behaviour a user typing "coffee " would see.
    static func matches(_ searchQuery: String, in texts: [String?]) -> Bool {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        let needle = searchQuery.lowercased()
        for text in texts {
            guard let text else { continue }
            if text.lowercased().contains(needle) { return true }
        }
        return false
    }

    static func searched<T>(
        _ items: [T],
        query: String,
        searchableText: (T) -> [String?]
    ) -> [T] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return items }
        return items.filter { matches(query, in: searchableText($0)) }
    }

    // MARK: - Sorting

    /// `isReordering` forces the fixed ascending priority order, exactly as the
    /// screens do (`result.sort((a, b) => (a.priority || 0) - (b.priority || 0))`)
    /// — during reorder the up/down arrows only make sense against the stored
    /// priority, so the chosen sort and direction are ignored.
    static func sorted<T>(
        _ items: [T],
        by key: SortKey,
        ascending: Bool,
        isReordering: Bool = false,
        name: (T) -> String,
        priority: (T) -> Int
    ) -> [T] {
        if isReordering {
            return orderedByPriority(items, priority: priority)
        }
        // `Array.prototype.sort` is stable, so equal keys keep the `ORDER BY
        // priority ASC, name ASC` order the rows were read in; Swift's
        // `sorted(by:)` is not, so equal keys are explicitly restored.
        return items.enumerated()
            .sorted { lhs, rhs in
                let comparison = compare(lhs.element, rhs.element, by: key, name: name, priority: priority)
                if comparison == 0 { return lhs.offset < rhs.offset }
                return ascending ? comparison < 0 : comparison > 0
            }
            .map(\.element)
    }

    /// The reorder view's order: priority ascending, ties in fetch order.
    static func orderedByPriority<T>(_ items: [T], priority: (T) -> Int) -> [T] {
        items.enumerated()
            .sorted { lhs, rhs in
                let left = priority(lhs.element)
                let right = priority(rhs.element)
                if left == right { return lhs.offset < rhs.offset }
                return left < right
            }
            .map(\.element)
    }

    private static func compare<T>(
        _ lhs: T,
        _ rhs: T,
        by key: SortKey,
        name: (T) -> String,
        priority: (T) -> Int
    ) -> Int {
        switch key {
        case .name:
            // JS `a.name.localeCompare(b.name)` — locale-aware collation.
            switch name(lhs).localizedCompare(name(rhs)) {
            case .orderedAscending: return -1
            case .orderedDescending: return 1
            case .orderedSame: return 0
            }
        case .priority:
            return sign(priority(lhs) - priority(rhs))
        }
    }

    private static func sign(_ value: Int) -> Int {
        if value < 0 { return -1 }
        if value > 0 { return 1 }
        return 0
    }

    // MARK: - Reordering

    /// What a move writes back: every visible row renumbered from `1`, in the order
    /// it is now displayed. The source does exactly this (`newData.map((item, i) =>
    /// ({ ...item, priority: i + 1 }))`) — the whole visible set is renumbered, not
    /// just the two swapped rows, so priorities stay dense.
    static func prioritiesAfterMove<T>(
        _ orderedItems: [T],
        id: (T) -> String
    ) -> [(id: String, priority: Int)] {
        orderedItems.enumerated().map { (id($0.element), $0.offset + 1) }
    }

    /// Moves one row within the list, before the whole visible set is renumbered.
    ///
    /// `insertionOffset` follows SwiftUI's `onMove` convention — the index the row
    /// is dropped *before*, counted in the pre-removal list — which is why a move
    /// downwards is adjusted by one. The reorder arrows call it with
    /// `index - 1` / `index + 2`, reproducing the source's `moveItem(index, 'up' |
    /// 'down')` swap exactly.
    static func moved<T>(_ items: [T], from source: Int, to insertionOffset: Int) -> [T] {
        guard items.indices.contains(source) else { return items }
        var result = items
        let moved = result.remove(at: source)
        let target = insertionOffset > source ? insertionOffset - 1 : insertionOffset
        result.insert(moved, at: min(max(target, 0), result.count))
        return result
    }
}
