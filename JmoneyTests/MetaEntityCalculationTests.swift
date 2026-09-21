import XCTest

@testable import Jmoney

/// The pure half of Phase 12: the shared search/sort helper, the four services'
/// filter+sort wrappers, the Material → SF Symbol table, and the view-mode
/// preference.
final class MetaEntityCalculationTests: XCTestCase {
    // MARK: - Fixtures

    private func category(
        _ id: String,
        _ name: String,
        type: String = "Expense",
        priority: Int = 0,
        appIcon: String? = nil
    ) -> Jmoney.Category {
        Jmoney.Category(
            id: id, name: name, type: type, icon: "", appIcon: appIcon, userId: "u1",
            isLivingCost: 0, syncStatus: 0, priority: priority
        )
    }

    private func payee(_ id: String, _ name: String, priority: Int = 0) -> Payee {
        Payee(id: id, name: name, logo: "", userId: "u1", syncStatus: 0, priority: priority)
    }

    private func group(
        _ id: String,
        _ name: String,
        description: String? = nil,
        priority: Int = 0
    ) -> TransactionGroup {
        TransactionGroup(
            id: id, name: name, description: description, userId: "u1", priority: priority,
            syncStatus: 0
        )
    }

    private func template(
        _ id: String,
        _ name: String,
        type: String = "Expense",
        amount: Double? = 100,
        description: String? = nil,
        priority: Int = 0
    ) -> QuickTransaction {
        QuickTransaction(
            id: id, name: name, type: type, amount: amount, categoryId: nil, payeeId: nil,
            description: description, userId: "u1", productLink: nil, priority: priority,
            identifier: nil, syncStatus: 0, deleted: 0
        )
    }

    // MARK: - Search semantics

    func testSearchIsCaseInsensitiveSubstring() {
        XCTAssertTrue(EntityOrdering.matches("coffee", in: ["Morning Coffee"]))
        XCTAssertTrue(EntityOrdering.matches("COFFEE", in: ["Morning Coffee"]))
        XCTAssertFalse(EntityOrdering.matches("tea", in: ["Morning Coffee"]))
    }

    func testAnAllWhitespaceQueryDoesNotFilter() {
        XCTAssertTrue(EntityOrdering.matches("   ", in: ["Anything"]))
        XCTAssertEqual(
            EntityOrdering.searched(["a", "b"], query: "  ", searchableText: { [$0] }),
            ["a", "b"]
        )
    }

    /// Preserved source quirk: the gate trims the query but the needle does not, so
    /// a trailing space can only match text that itself has a space there.
    func testATrailingSpaceInTheQueryIsSignificant() {
        XCTAssertFalse(EntityOrdering.matches("coffee ", in: ["Coffee"]))
        XCTAssertTrue(EntityOrdering.matches("coffee ", in: ["Coffee Shop"]))
    }

    func testNilSearchableTextIsSkipped() {
        XCTAssertFalse(EntityOrdering.matches("trip", in: [nil, nil]))
        XCTAssertTrue(EntityOrdering.matches("trip", in: [nil, "Europe trip"]))
    }

    // MARK: - Sorting

    func testSortByPriorityAppliesTheDirection() {
        let items = [payee("a", "A", priority: 2), payee("b", "B", priority: 1)]

        let ascending = EntityOrdering.sorted(
            items, by: .priority, ascending: true, name: \.name, priority: \.priority
        )
        XCTAssertEqual(ascending.map(\.id), ["b", "a"])

        let descending = EntityOrdering.sorted(
            items, by: .priority, ascending: false, name: \.name, priority: \.priority
        )
        XCTAssertEqual(descending.map(\.id), ["a", "b"])
    }

    /// `Array.prototype.sort` is stable, so equal keys keep the fetch order
    /// (`priority ASC, name ASC`); the port restores that explicitly.
    func testTiesKeepTheirInputOrderInBothDirections() {
        let items = [
            payee("a", "Alpha", priority: 1),
            payee("b", "Beta", priority: 1),
            payee("c", "Gamma", priority: 2),
        ]

        let ascending = EntityOrdering.sorted(
            items, by: .priority, ascending: true, name: \.name, priority: \.priority
        )
        XCTAssertEqual(ascending.map(\.id), ["a", "b", "c"])

        let descending = EntityOrdering.sorted(
            items, by: .priority, ascending: false, name: \.name, priority: \.priority
        )
        XCTAssertEqual(descending.map(\.id), ["c", "a", "b"], "ties stay in input order")
    }

    /// Reorder mode ignores the chosen sort and direction entirely.
    func testReorderingForcesAscendingPriority() {
        let items = [payee("a", "A", priority: 3), payee("b", "B", priority: 1)]

        let result = EntityOrdering.sorted(
            items, by: .name, ascending: false, isReordering: true,
            name: \.name, priority: \.priority
        )
        XCTAssertEqual(result.map(\.id), ["b", "a"])
    }

    func testPrioritiesAfterMoveRenumbersFromOne() {
        let ordered = [payee("b", "B"), payee("c", "C"), payee("a", "A")]
        let updates = EntityOrdering.prioritiesAfterMove(ordered, id: \.id)
        XCTAssertEqual(updates.map(\.id), ["b", "c", "a"])
        XCTAssertEqual(updates.map(\.priority), [1, 2, 3])
    }

    /// The move helper follows SwiftUI's `onMove` insertion-offset convention, which
    /// is what lets the up/down arrows reproduce the source's swap.
    func testMovedFollowsInsertionOffsetSemantics() {
        let items = [payee("a", "A"), payee("b", "B"), payee("c", "C")]

        XCTAssertEqual(
            EntityOrdering.moved(items, from: 1, to: 0).map(\.id), ["b", "a", "c"], "up"
        )
        XCTAssertEqual(
            EntityOrdering.moved(items, from: 0, to: 2).map(\.id), ["b", "a", "c"], "down"
        )
        XCTAssertEqual(
            EntityOrdering.moved(items, from: 0, to: 1).map(\.id), ["a", "b", "c"], "no-op"
        )
    }

    func testMovedClampsAtBothEnds() {
        let items = [payee("a", "A"), payee("b", "B")]

        XCTAssertEqual(EntityOrdering.moved(items, from: 0, to: -1).map(\.id), ["a", "b"])
        XCTAssertEqual(EntityOrdering.moved(items, from: 1, to: 4).map(\.id), ["a", "b"])
        XCTAssertEqual(EntityOrdering.moved(items, from: 9, to: 0).map(\.id), ["a", "b"])
    }

    // MARK: - Category filter/sort

    func testCategoryFilterSplitsTheTabsAndSearchesTheNameOnly() {
        let categories = [
            category("c1", "Groceries", type: "Expense", priority: 1),
            category("c2", "General", type: "Expense", priority: 2),
            category("c3", "Salary", type: "Income", priority: 1),
        ]

        let expenses = CategoryService.filterAndSort(
            categories, activeTab: .expense, searchQuery: "", sortBy: .priority, ascending: true,
            isReordering: false
        )
        XCTAssertEqual(expenses.map(\.id), ["c1", "c2"])

        let incomes = CategoryService.filterAndSort(
            categories, activeTab: .income, searchQuery: "", sortBy: .priority, ascending: true,
            isReordering: false
        )
        XCTAssertEqual(incomes.map(\.id), ["c3"])

        // "Salary" is an Income category, so the Expense tab finds nothing for it.
        let crossTab = CategoryService.filterAndSort(
            categories, activeTab: .expense, searchQuery: "salary", sortBy: .priority,
            ascending: true, isReordering: false
        )
        XCTAssertTrue(crossTab.isEmpty)
    }

    func testCategorySortByNameAppliesTheDirection() {
        let categories = [
            category("c1", "Zebra", priority: 1),
            category("c2", "Apple", priority: 2),
        ]

        XCTAssertEqual(
            CategoryService.filterAndSort(
                categories, activeTab: .expense, searchQuery: "", sortBy: .name, ascending: true,
                isReordering: false
            ).map(\.id),
            ["c2", "c1"]
        )
        XCTAssertEqual(
            CategoryService.filterAndSort(
                categories, activeTab: .expense, searchQuery: "", sortBy: .name, ascending: false,
                isReordering: false
            ).map(\.id),
            ["c1", "c2"]
        )
    }

    // MARK: - Group filter/sort

    /// Groups are the one screen whose search covers the description as well.
    func testGroupSearchMatchesTheDescription() {
        let groups = [
            group("g1", "Europe Trip", description: "Summer 2026", priority: 1),
            group("g2", "Home Renovation", description: nil, priority: 2),
        ]

        XCTAssertEqual(
            GroupService.filterAndSort(
                groups, searchQuery: "summer", sortBy: .priority, ascending: true,
                isReordering: false
            ).map(\.id),
            ["g1"]
        )
        XCTAssertEqual(
            GroupService.filterAndSort(
                groups, searchQuery: "reno", sortBy: .priority, ascending: true,
                isReordering: false
            ).map(\.id),
            ["g2"]
        )
    }

    // MARK: - Quick-transaction filter/sort

    /// The quick-transactions screen trims its needle (unlike the other three) and
    /// always orders by priority.
    func testQuickTransactionFilterTrimsTheQueryAndIgnoresDescription() {
        let templates = [
            template("q1", "Morning Coffee", priority: 2),
            template("q2", "Lunch", description: "coffee runs", priority: 1),
        ]

        XCTAssertEqual(
            QuickTransactionService.filterAndSort(templates, searchQuery: "Coffee").map(\.id),
            ["q1"],
            "the description is not searched, and the needle is trimmed"
        )

        // No sort menu: the order is priority ascending, reorder mode or not.
        XCTAssertEqual(
            QuickTransactionService.filterAndSort(templates, searchQuery: "").map(\.id),
            ["q2", "q1"]
        )
    }

    // MARK: - View mode preference

    func testViewModeDefaultsMatchTheSource() {
        let defaults = UserDefaults(suiteName: "phase12-\(UUID().uuidString)")!

        XCTAssertEqual(
            ViewModePreference.listGridMode(for: .categories, userId: "u1", defaults: defaults),
            .grid
        )
        XCTAssertEqual(ViewModePreference.cardListMode(userId: "u1", defaults: defaults), .card)

        // An unrecognised value falls back to the default, exactly as the source's
        // `viewMode === 'list' || viewMode === 'grid' ? … : 'grid'` does.
        ViewModePreference.save("nonsense", for: .payees, userId: "u1", defaults: defaults)
        XCTAssertEqual(
            ViewModePreference.listGridMode(for: .payees, userId: "u1", defaults: defaults),
            .grid
        )
    }

    func testViewModeRoundTripsTheSourceLiteralsAndIsScopedPerUser() {
        let defaults = UserDefaults(suiteName: "phase12-\(UUID().uuidString)")!

        ViewModePreference.save("list", for: .categories, userId: "u1", defaults: defaults)
        XCTAssertEqual(
            ViewModePreference.listGridMode(for: .categories, userId: "u1", defaults: defaults),
            .list
        )
        XCTAssertEqual(
            ViewModePreference.listGridMode(for: .categories, userId: "u2", defaults: defaults),
            .grid,
            "another user has their own preference"
        )

        // The quick-transactions screen is the one whose literals are capitalised.
        ViewModePreference.save("List", for: .quickTransactions, userId: "u1", defaults: defaults)
        XCTAssertEqual(ViewModePreference.cardListMode(userId: "u1", defaults: defaults), .list)
        XCTAssertEqual(
            ViewModePreference.storedValue(for: .quickTransactions, userId: "u1", defaults: defaults),
            "List"
        )
    }

    func testViewModeKeysMatchTheSourceStorageKeys() {
        XCTAssertEqual(
            ViewModePreference.Screen.categories.storageKey(userId: "u1"),
            "@category_view_mode_u1"
        )
        XCTAssertEqual(
            ViewModePreference.Screen.quickTransactions.storageKey(userId: "u1"),
            "@quick_transaction_view_mode_u1"
        )
    }

    // MARK: - Icon mapping

    func testFormatIconNameStripsTheMdPrefixAndKebabCases() {
        XCTAssertEqual(CategoryIcon.normalizedMaterialName("MdLocalGasStation"), "local-gas-station")
        XCTAssertEqual(CategoryIcon.normalizedMaterialName("MdHome"), "home")
        XCTAssertEqual(CategoryIcon.normalizedMaterialName("  fastfood "), "fastfood")
        XCTAssertNil(CategoryIcon.normalizedMaterialName(""))
        XCTAssertNil(CategoryIcon.normalizedMaterialName("   "))
        XCTAssertNil(CategoryIcon.normalizedMaterialName(nil))
    }

    func testKnownNamesMapToSymbols() {
        XCTAssertEqual(CategoryIcon.symbolName(for: "fastfood"), "fork.knife")
        XCTAssertEqual(CategoryIcon.symbolName(for: "MdHome"), "house")
        XCTAssertEqual(CategoryIcon.symbolName(for: "directions_car"), "tag", "underscores are not normalised")
        XCTAssertEqual(CategoryIcon.symbolName(for: "directions-car"), "car")
    }

    func testUnknownAndEmptyNamesFallBack() {
        XCTAssertEqual(CategoryIcon.symbolName(for: nil), CategoryIcon.fallbackSymbolName)
        XCTAssertEqual(CategoryIcon.symbolName(for: "not-a-real-icon"), CategoryIcon.fallbackSymbolName)
        XCTAssertFalse(CategoryIcon.isMapped("not-a-real-icon"))
        XCTAssertTrue(CategoryIcon.isMapped("fastfood"))
    }

    /// The source's per-context defaults: `'receipt'` for a transaction or a report
    /// row, `'category'` for a category.
    func testContextFallbacksMatchTheSource() {
        XCTAssertEqual(CategoryIcon.transactionSymbol(nil), "doc.text")
        XCTAssertEqual(CategoryIcon.transactionSymbol(""), "doc.text")
        XCTAssertEqual(CategoryIcon.transactionSymbol("flight"), "airplane")

        XCTAssertEqual(CategoryIcon.categorySymbol(nil), "square.grid.2x2")
        XCTAssertEqual(CategoryIcon.categorySymbol("fastfood"), "fork.knife")

        XCTAssertEqual(CategoryIcon.configTileSymbol(nil), "doc.text")
        XCTAssertEqual(
            CategoryIcon.reportSymbol(categoryAppIcon: nil, appIcon: "fastfood"), "fork.knife",
            "`category_app_icon || app_icon || 'receipt'`"
        )
        XCTAssertEqual(
            CategoryIcon.reportSymbol(categoryAppIcon: "flight", appIcon: "fastfood"), "airplane"
        )
        XCTAssertEqual(CategoryIcon.reportSymbol(categoryAppIcon: nil, appIcon: nil), "doc.text")
    }

    /// Every offerable name resolves through the table. A few of them *are* the
    /// fallback glyph ("label", "local-offer", "sell" all map to `tag`), so the
    /// assertion is that the entry exists and yields a symbol, not that it differs.
    func testEveryOfferableNameHasASymbol() {
        XCTAssertFalse(CategoryIcon.offerableMaterialNames.isEmpty)
        for name in CategoryIcon.offerableMaterialNames {
            XCTAssertTrue(CategoryIcon.isMapped(name), "\(name) is offerable but unmapped")
            XCTAssertFalse(CategoryIcon.symbolName(for: name).isEmpty)
            XCTAssertEqual(
                CategoryIcon.symbolName(for: name), CategoryIcon.table[name],
                "\(name) is offerable but does not resolve through the table"
            )
        }
    }
}
