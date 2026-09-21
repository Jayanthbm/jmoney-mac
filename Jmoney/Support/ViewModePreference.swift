import Foundation

/// The per-screen list/grid preference.
///
/// The React Native screens persist these in AsyncStorage under
/// `@category_view_mode_<userId>`, `@payee_view_mode_<userId>`,
/// `@group_view_mode_<userId>` and `@quick_transaction_view_mode_<userId>`
/// (DATA_ARCHITECTURE.md §1.5). macOS has no AsyncStorage; `UserDefaults` is the
/// equivalent store, so only the storage medium changes — the keys, the per-user
/// scoping, and the defaults do not.
///
/// The stored values are the source's own literals (`"grid"`/`"list"` for
/// categories/payees/groups, `"Card"`/`"List"` for quick transactions), and an
/// unrecognised or absent value falls back to the screen's default.
enum ViewModePreference {
    /// A key names the screen; the user id is appended, as in the source.
    ///
    /// The raw values are the source's own key fragments — singular for categories,
    /// payees and groups (`@payee_view_mode_<user>`), so they are spelled out rather
    /// than derived from the case names.
    enum Screen: String {
        case categories = "category"
        case payees = "payee"
        case groups = "group"
        case quickTransactions = "quick_transaction"

        /// Mirrors `@category_view_mode_<user>` etc.
        func storageKey(userId: String) -> String {
            "@\(rawValue)_view_mode_\(userId)"
        }
    }

    static func storedValue(for screen: Screen, userId: String, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: screen.storageKey(userId: userId))
    }

    static func save(
        _ value: String,
        for screen: Screen,
        userId: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(value, forKey: screen.storageKey(userId: userId))
    }

    /// `viewMode === 'list' || viewMode === 'grid' ? viewMode : 'grid'`.
    static func listGridMode(
        for screen: Screen,
        userId: String,
        defaults: UserDefaults = .standard
    ) -> ListGridMode {
        let stored = storedValue(for: screen, userId: userId, defaults: defaults)
        return stored.flatMap(ListGridMode.init(rawValue:)) ?? .grid
    }

    /// `viewMode === 'Card' || viewMode === 'List' ? viewMode : 'Card'`.
    static func cardListMode(
        userId: String,
        defaults: UserDefaults = .standard
    ) -> CardListMode {
        let stored = storedValue(for: .quickTransactions, userId: userId, defaults: defaults)
        return stored.flatMap(CardListMode.init(rawValue:)) ?? .card
    }

    /// The literal values the source stores for categories/payees/groups.
    enum ListGridMode: String {
        case list
        case grid

        var toggled: ListGridMode { self == .list ? .grid : .list }
    }

    /// The literal values the source stores for quick transactions. Note the
    /// capitalisation — the quick-transactions screen is the one screen whose
    /// values are not lowercase.
    enum CardListMode: String {
        case card = "Card"
        case list = "List"

        var toggled: CardListMode { self == .card ? .list : .card }
    }
}
