import GRDB
import XCTest

@testable import Jmoney

/// Verifies the four management-entity services against the RN queries: scoping,
/// the `priority ASC, name ASC` order, the auto-assigned priority, the upsert, and
/// each entity's delete shape (`groups` hard, `quick_transactions` soft, categories
/// and payees none at all).
final class MetaEntityServiceTests: XCTestCase {
    private let user = "u1"

    private func makeDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try DatabaseService.migrator.migrate(dbQueue)
        return dbQueue
    }

    // MARK: - Fixtures

    private func insertCategory(
        _ db: Database,
        id: String,
        name: String,
        type: String = "Expense",
        appIcon: String = "fastfood",
        priority: Int = 0,
        userId: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO categories
                    (id, name, type, icon, app_icon, user_id, is_living_cost, priority, sync_status)
                VALUES (?, ?, ?, '', ?, ?, 0, ?, 0)
                """,
            arguments: [id, name, type, appIcon, userId ?? self.user, priority]
        )
    }

    private func insertPayee(
        _ db: Database,
        id: String,
        name: String,
        logo: String = "",
        priority: Int = 0,
        userId: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO payees (id, name, logo, user_id, priority, sync_status)
                VALUES (?, ?, ?, ?, ?, 0)
                """,
            arguments: [id, name, logo, userId ?? self.user, priority]
        )
    }

    private func insertGroup(
        _ db: Database,
        id: String,
        name: String,
        description: String? = nil,
        priority: Int = 0,
        userId: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO transaction_groups
                    (id, name, description, user_id, priority, sync_status)
                VALUES (?, ?, ?, ?, ?, 0)
                """,
            arguments: [id, name, description, userId ?? self.user, priority]
        )
    }

    private func insertTemplate(
        _ db: Database,
        id: String,
        name: String,
        type: String = "Expense",
        amount: Double? = nil,
        priority: Int = 0,
        deleted: Int = 0,
        userId: String? = nil
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO quick_transactions
                    (id, name, type, amount, user_id, priority, sync_status, deleted)
                VALUES (?, ?, ?, ?, ?, ?, 0, ?)
                """,
            arguments: [id, name, type, amount, userId ?? self.user, priority, deleted]
        )
    }

    private func insertTransaction(
        _ db: Database,
        id: String,
        amount: Double = 100,
        groupId: String? = nil,
        deleted: Int = 0
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO transactions
                    (id, amount, transaction_timestamp, date, type, user_id, tid,
                     sync_status, deleted, group_id)
                VALUES (?, ?, '2026-09-01T00:00:00.000Z', '2026-09-01', 'Expense', ?, 0, 0, ?, ?)
                """,
            arguments: [id, amount, user, deleted, groupId]
        )
    }

    private func makeSeededDatabase() throws -> DatabaseQueue {
        let dbQueue = try makeDatabase()
        try dbQueue.write { db in
            try insertCategory(db, id: "c1", name: "Groceries", priority: 1)
            try insertCategory(db, id: "c2", name: "General", priority: 2)
            try insertCategory(db, id: "c3", name: "Salary", type: "Income", priority: 1)
            try insertCategory(db, id: "c4", name: "Other", priority: 1, userId: "u2")

            try insertPayee(db, id: "p1", name: "Alpha", priority: 1)
            try insertPayee(db, id: "p2", name: "Beta", priority: 2)

            try insertGroup(db, id: "g1", name: "Europe", description: "Trip", priority: 1)
            try insertGroup(db, id: "g2", name: "Home", description: nil, priority: 2)

            try insertTemplate(db, id: "q1", name: "Coffee", amount: 120, priority: 1)
            try insertTemplate(db, id: "q2", name: "Lunch", priority: 2)
            try insertTemplate(db, id: "q3", name: "Deleted", priority: 3, deleted: 1)

            try insertTransaction(db, id: "t1", groupId: "g1")
            try insertTransaction(db, id: "t2", groupId: "g1")
            try insertTransaction(db, id: "t3", groupId: "g1", deleted: 1)
        }
        return dbQueue
    }

    // MARK: - Reads

    func testCategoriesAreUserScopedAndPriorityOrdered() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            let rows = try CategoryService.categories(userId: user, in: db)
            XCTAssertEqual(rows.map(\.id), ["c1", "c3", "c2"], "priority ASC, name ASC")
            XCTAssertTrue(try CategoryService.categories(userId: "nobody", in: db).isEmpty)
        }
    }

    func testPayeesAreUserScopedAndPriorityOrdered() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            XCTAssertEqual(try PayeeService.payees(userId: user, in: db).map(\.id), ["p1", "p2"])
        }
    }

    func testGroupsArePriorityOrdered() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            XCTAssertEqual(try GroupService.groups(userId: user, in: db).map(\.id), ["g1", "g2"])
        }
    }

    /// The source filters `deleted = 0` here (`getQuickTransactions`).
    func testQuickTransactionsExcludeSoftDeletedRows() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            XCTAssertEqual(
                try QuickTransactionService.quickTransactions(userId: user, in: db).map(\.id),
                ["q1", "q2"]
            )
        }
    }

    func testUnsyncedQuickTransactionsSelectsDirtyRows() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE quick_transactions SET sync_status = 1 WHERE id = 'q1'"
            )
            let dirty = try QuickTransactionService.unsynced(userId: user, in: db)
            XCTAssertEqual(dirty.map(\.id), ["q1"])
        }
    }

    func testMaxPriorityIsZeroForAnEmptyTable() throws {
        let dbQueue = try makeDatabase()
        try dbQueue.read { db in
            XCTAssertEqual(try CategoryService.maxPriority(userId: user, in: db), 0)
            XCTAssertEqual(try PayeeService.maxPriority(userId: user, in: db), 0)
            XCTAssertEqual(try GroupService.maxPriority(userId: user, in: db), 0)
            XCTAssertEqual(try QuickTransactionService.maxPriority(userId: user, in: db), 0)
        }
    }

    // MARK: - Category writes

    func testNewCategoryAppendsToTheEndAndIsDirty() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            let draft = CategoryService.Draft(name: "  Rent  ", type: .expense, appIcon: " home ")
            let record = CategoryService.makeCategory(from: draft, userId: user) { "new" }
            XCTAssertEqual(record.name, "Rent", "trimmed")
            XCTAssertEqual(record.appIcon, "home", "trimmed")
            XCTAssertEqual(record.icon, "", "the legacy column is written as ''")
            XCTAssertEqual(record.userId, user)
            XCTAssertEqual(record.isLivingCost, 0)
            XCTAssertEqual(record.priority, 0, "assigned by the write")

            try CategoryService.save(record, in: db)

            let row = try Row.fetchOne(db, sql: "SELECT * FROM categories WHERE id = 'new'")!
            XCTAssertEqual(row["priority"] as Int, 3, "MAX(priority) + 1 across all types")
            XCTAssertEqual(row["sync_status"] as Int, 1)
            XCTAssertEqual(row["type"] as String, "Expense")
        }
    }

    /// An empty icon takes the source's `'category'` default.
    func testCategoryIconFallsBackToTheDefaultName() {
        let record = CategoryService.makeCategory(
            from: .init(name: "Misc", type: .income, appIcon: "   "),
            userId: user
        ) { "new" }
        XCTAssertEqual(record.appIcon, "category")
        XCTAssertEqual(CategoryIcon.symbolName(for: record.appIcon), "square.grid.2x2")
    }

    func testCategorySaveUpsertsInPlace() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            var existing = try Jmoney.Category.fetchOne(
                db, sql: "SELECT * FROM categories WHERE id = 'c1'"
            )!
            existing.name = "Groceries & Home"
            existing.priority = 1

            try CategoryService.save(existing, in: db)

            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id = 'c1'")
            XCTAssertEqual(count, 1)
            let row = try Row.fetchOne(db, sql: "SELECT * FROM categories WHERE id = 'c1'")!
            XCTAssertEqual(row["name"] as String, "Groceries & Home")
            XCTAssertEqual(row["priority"] as Int, 1, "an existing priority is not reassigned")
            XCTAssertEqual(row["app_icon"] as String, "fastfood", "untouched columns survive")
        }
    }

    func testCategoryReorderWritesPriorityAndDirtyFlagOnly() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            try CategoryService.updatePriorities(
                [(id: "c1", priority: 2), (id: "c2", priority: 1)], userId: user, in: db
            )

            // c1 Groceries and c2 General now share priority 1, so the name breaks
            // the tie; Salary (c3) keeps priority 1 too.
            let rows = try CategoryService.categories(userId: user, in: db)
            XCTAssertEqual(rows.map(\.id), ["c2", "c3", "c1"])

            let row = try Row.fetchOne(db, sql: "SELECT * FROM categories WHERE id = 'c1'")!
            XCTAssertEqual(row["priority"] as Int, 2)
            XCTAssertEqual(row["sync_status"] as Int, 1)
            XCTAssertEqual(row["app_icon"] as String, "fastfood", "reordering is not a rewrite")
            XCTAssertEqual(row["is_living_cost"] as Int, 0)
        }
    }

    func testCategoryReorderIsUserScoped() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            try CategoryService.updatePriorities([(id: "c4", priority: 99)], userId: user, in: db)
            let row = try Row.fetchOne(db, sql: "SELECT priority FROM categories WHERE id = 'c4'")!
            XCTAssertEqual(row["priority"] as Int, 1, "another user's category is untouched")
        }
    }

    // MARK: - Payee writes

    func testNewPayeeAppendsAndStoresATrimmedLogo() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            let draft = PayeeService.Draft(name: " Gamma ", logo: " https://x/y.png ")
            let record = PayeeService.makePayee(from: draft, userId: user) { "new" }
            XCTAssertEqual(record.name, "Gamma")
            XCTAssertEqual(record.logo, "https://x/y.png")

            try PayeeService.save(record, in: db)

            let row = try Row.fetchOne(db, sql: "SELECT * FROM payees WHERE id = 'new'")!
            XCTAssertEqual(row["priority"] as Int, 3)
            XCTAssertEqual(row["sync_status"] as Int, 1)
        }
    }

    /// Unlike a category, an empty payee logo stays `''` — the card falls back to the
    /// name's initial rather than to a placeholder icon.
    func testPayeeWithNoLogoStoresAnEmptyString() {
        let record = PayeeService.makePayee(
            from: .init(name: "Cash", logo: ""), userId: user
        ) { "new" }
        XCTAssertEqual(record.logo, "")
    }

    // MARK: - Group writes

    func testNewGroupMapsAnEmptyDescriptionToNull() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            let record = GroupService.makeGroup(
                from: .init(existing: nil, name: "  Trip  ", description: "   "),
                userId: user
            ) { "new" }
            XCTAssertEqual(record.name, "Trip")
            XCTAssertNil(record.description, "`description?.trim() || null`")
            XCTAssertEqual(record.syncStatus, 1)

            try GroupService.save(record, in: db)

            let row = try Row.fetchOne(db, sql: "SELECT * FROM transaction_groups WHERE id = 'new'")!
            XCTAssertEqual(row["priority"] as Int, 3)
            XCTAssertTrue(row["description"] as String? == nil)
        }
    }

    func testEditingAGroupKeepsItsPriorityAndID() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            let existing = try TransactionGroup.fetchOne(
                db, sql: "SELECT * FROM transaction_groups WHERE id = 'g1'"
            )!
            let record = GroupService.makeGroup(
                from: .init(existing: existing, name: "Europe 2027", description: " Next summer "),
                userId: user
            )
            XCTAssertEqual(record.id, "g1")
            XCTAssertEqual(record.priority, 1, "carried through, not reassigned")

            try GroupService.save(record, in: db)

            let count = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM transaction_groups WHERE id = 'g1'"
            )
            XCTAssertEqual(count, 1)
            let row = try Row.fetchOne(db, sql: "SELECT * FROM transaction_groups WHERE id = 'g1'")!
            XCTAssertEqual(row["name"] as String, "Europe 2027")
            XCTAssertEqual(row["description"] as String, "Next summer")
            XCTAssertEqual(row["priority"] as Int, 1)
            XCTAssertEqual(row["sync_status"] as Int, 1)
        }
    }

    /// The phase's most consequential write: the group row goes, its member
    /// transactions stay and keep the now-dangling `group_id`.
    func testGroupDeleteIsHardAndLeavesMemberTransactionsAlone() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            XCTAssertEqual(try GroupService.hardDelete(id: "g1", userId: user, in: db), 1)

            let groups = try GroupService.groups(userId: user, in: db)
            XCTAssertEqual(groups.map(\.id), ["g2"], "the row is gone, not flagged")

            let members = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM transactions WHERE group_id = 'g1'"
            )
            XCTAssertEqual(members, 3, "every member row keeps the now-dangling reference")
        }
    }

    func testGroupDeleteIsUserScoped() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            XCTAssertEqual(try GroupService.hardDelete(id: "g1", userId: "u2", in: db), 0)
            XCTAssertEqual(try GroupService.groups(userId: user, in: db).count, 2)
        }
    }

    func testMemberTransactionCountIgnoresSoftDeletedRows() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.read { db in
            XCTAssertEqual(
                try GroupService.memberTransactionCount(id: "g1", userId: user, in: db), 2
            )
            XCTAssertEqual(
                try GroupService.memberTransactionCount(id: "g2", userId: user, in: db), 0
            )
        }
    }

    // MARK: - Quick-transaction writes

    func testNewTemplateAppendsAndIsBornDirty() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            let record = QuickTransactionService.makeQuickTransaction(
                from: .init(
                    existing: nil, name: " Tea ", type: .expense, amount: 60, categoryId: "c1",
                    payeeId: "p1", description: " chai ", productLink: " https://x ",
                    identifier: "tp"
                ),
                userId: user
            ) { "new" }
            XCTAssertEqual(record.name, "Tea")
            XCTAssertEqual(record.priority, 0)

            try QuickTransactionService.save(record, in: db)

            let row = try Row.fetchOne(db, sql: "SELECT * FROM quick_transactions WHERE id = 'new'")!
            XCTAssertEqual(row["priority"] as Int, 4, "MAX(priority) + 1, including deleted rows")
            XCTAssertEqual(row["sync_status"] as Int, 1, "new templates are born dirty")
            XCTAssertEqual(row["deleted"] as Int, 0)
            XCTAssertEqual(row["amount"] as Double, 60)
            XCTAssertEqual(row["description"] as String, "chai")
            XCTAssertEqual(row["identifier"] as String, "TP", "upper-cased")
        }
    }

    /// `identifier.trim().toUpperCase().slice(0, 2) || undefined`.
    func testIdentifierIsTruncatedToTwoCharactersAndEmptyBecomesNull() throws {
        let long = QuickTransactionService.makeQuickTransaction(
            from: .init(
                existing: nil, name: "A", type: .expense, amount: nil, categoryId: nil,
                payeeId: nil, description: "", productLink: "", identifier: " coffee "
            ),
            userId: user
        ) { "new" }
        XCTAssertEqual(long.identifier, "CO")

        let empty = QuickTransactionService.makeQuickTransaction(
            from: .init(
                existing: nil, name: "A", type: .expense, amount: nil, categoryId: nil,
                payeeId: nil, description: "", productLink: "", identifier: "   "
            ),
            userId: user
        ) { "new" }
        XCTAssertNil(empty.identifier)
    }

    /// The `|| null` idioms: a zero amount, an empty description and an empty link all
    /// become SQL `NULL` rather than `0`/`''`.
    func testZeroAmountAndEmptyStringsBecomeNull() {
        let record = QuickTransactionService.makeQuickTransaction(
            from: .init(
                existing: nil, name: "Flexible", type: .expense, amount: 0, categoryId: nil,
                payeeId: nil, description: "  ", productLink: "", identifier: ""
            ),
            userId: user
        ) { "new" }
        XCTAssertNil(record.amount, "JS `0 || null` is null")
        XCTAssertNil(record.description)
        XCTAssertNil(record.productLink)
        XCTAssertNil(record.identifier)
    }

    func testEditingATemplateKeepsItsPriorityAndDoesNotReviveIt() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            let existing = try QuickTransaction.fetchOne(
                db, sql: "SELECT * FROM quick_transactions WHERE id = 'q1'"
            )!
            let record = QuickTransactionService.makeQuickTransaction(
                from: .init(
                    existing: existing, name: "Espresso", type: .expense, amount: 150,
                    categoryId: nil, payeeId: nil, description: "", productLink: "",
                    identifier: existing.identifier ?? ""
                ),
                userId: user
            )
            XCTAssertEqual(record.id, "q1")
            XCTAssertEqual(record.priority, 1)

            try QuickTransactionService.save(record, in: db)

            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM quick_transactions WHERE id = 'q1'")
            XCTAssertEqual(count, 1)
            let row = try Row.fetchOne(db, sql: "SELECT * FROM quick_transactions WHERE id = 'q1'")!
            XCTAssertEqual(row["name"] as String, "Espresso")
            XCTAssertEqual(row["amount"] as Double, 150)
            XCTAssertEqual(row["priority"] as Int, 1)
            XCTAssertEqual(row["deleted"] as Int, 0)
            XCTAssertEqual(row["sync_status"] as Int, 1)
        }
    }

    func testTemplateDeleteIsSoftOnly() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            XCTAssertEqual(
                try QuickTransactionService.softDelete(id: "q1", userId: user, in: db), 1
            )

            let row = try Row.fetchOne(db, sql: "SELECT * FROM quick_transactions WHERE id = 'q1'")!
            XCTAssertEqual(row["deleted"] as Int, 1)
            XCTAssertEqual(row["sync_status"] as Int, 1)

            XCTAssertEqual(
                try QuickTransactionService.quickTransactions(userId: user, in: db).map(\.id),
                ["q2"],
                "the row stays for the push, but disappears from every read"
            )
        }
    }

    func testTemplateDeleteIsUserScoped() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            XCTAssertEqual(
                try QuickTransactionService.softDelete(id: "q1", userId: "u2", in: db), 0
            )
        }
    }

    // MARK: - Quick-transaction prefill

    func testPrefillCarriesTypeAmountDescriptionCategoryAndPayee() {
        let lookups = TransactionService.Lookups(
            categories: [
                Jmoney.Category(
                    id: "c1", name: "Groceries", type: "Expense", icon: "", appIcon: "cart",
                    userId: user, isLivingCost: 0, syncStatus: 0, priority: 1
                )
            ],
            payees: [Payee(id: "p1", name: "Alpha", logo: "", userId: user, syncStatus: 0, priority: 1)],
            groups: []
        )
        let subject = QuickTransaction(
            id: "q1", name: "Coffee", type: "Income", amount: 120, categoryId: "c1",
            payeeId: "p1", description: "Morning brew", userId: user,
            productLink: "https://example.com", priority: 1, identifier: "CO",
            syncStatus: 0, deleted: 0
        )

        let prefill = TransactionService.prefill(from: subject, lookups: lookups)
        XCTAssertEqual(prefill.type, "Income")
        XCTAssertEqual(prefill.amount, 120)
        XCTAssertEqual(prefill.description, "Morning brew")
        XCTAssertEqual(prefill.categoryId, "c1")
        XCTAssertEqual(prefill.payeeId, "p1")
    }

    /// Preserved quirk: the template's product link is never applied, and nothing
    /// else carries its identifier or name.
    func testPrefillOmitsTheProductLinkUnlessTheCategoryStillExists() {
        let empty = TransactionService.Lookups.empty
        let subject = QuickTransaction(
            id: "q1", name: "Coffee", type: "Expense", amount: 120, categoryId: "gone",
            payeeId: "gone", description: "", userId: user, productLink: "https://example.com",
            priority: 1, identifier: "CO", syncStatus: 0, deleted: 0
        )

        let prefill = TransactionService.prefill(from: subject, lookups: empty)
        XCTAssertNil(prefill.categoryId, "a template can outlive the category it points at")
        XCTAssertNil(prefill.payeeId)
        XCTAssertNil(prefill.description, "'' is not a description")
        XCTAssertEqual(prefill.amount, 120)
        // `TemplatePrefill` has no product-link or group member at all: the source
        // applies neither.
    }

    /// A template opens the *add* flow (the prefill itself is applied once the
    /// lookups load, so it is covered by `testPrefillCarriesTypeAmount…` above).
    func testEditorAcceptsATemplateWithoutApplyingADefaultCategory() {
        let subject = QuickTransaction(
            id: "q1", name: "Coffee", type: "Income", amount: 120, categoryId: "c1",
            payeeId: nil, description: nil, userId: user, productLink: nil, priority: 1,
            identifier: nil, syncStatus: 0, deleted: 0
        )
        let viewModel = TransactionEditorViewModel(mode: .new, template: subject)

        XCTAssertFalse(viewModel.isEditing, "a template opens the add flow")
        XCTAssertTrue(viewModel.typeIsEditable)
        XCTAssertEqual(viewModel.template?.id, "q1")

        // Switching the type on a template draft does not re-apply "general"/"salary"
        // — the source guards that effect with `!quickTx`.
        viewModel.changeType(to: "Income")
        XCTAssertEqual(viewModel.type, "Income")
        XCTAssertNil(viewModel.selectedCategoryId)
    }

    /// The same switch on a plain new transaction *does* try to apply the default —
    /// with no lookups loaded there is simply no "salary" category to pick.
    func testEditorAppliesTheDefaultCategoryForAPlainDraft() {
        let viewModel = TransactionEditorViewModel(mode: .new)
        XCTAssertNil(viewModel.template)
        viewModel.changeType(to: "Income")
        XCTAssertEqual(viewModel.type, "Income")
    }

    // MARK: - Editor view models

    func testCategoryEditorRequiresAName() async {
        let viewModel = CategoryEditorViewModel()
        XCTAssertFalse(viewModel.canSave)

        let saved = await viewModel.save(pool: nil, userId: user)
        XCTAssertFalse(saved)
        XCTAssertTrue(viewModel.showsNameError)

        viewModel.name = "   "
        XCTAssertFalse(viewModel.canSave)

        viewModel.name = " Rent "
        XCTAssertTrue(viewModel.canSave)
        XCTAssertEqual(viewModel.draft.name, "Rent")
        XCTAssertEqual(viewModel.draft.type, .expense)
    }

    func testCategoryEditorPreviewsTheMappedSymbol() {
        let viewModel = CategoryEditorViewModel()
        XCTAssertEqual(viewModel.previewSymbolName, "square.grid.2x2", "the 'category' default")
        viewModel.appIcon = "flight"
        XCTAssertEqual(viewModel.previewSymbolName, "airplane")
    }

    func testPayeeEditorRecognisesOnlyHttpLogos() {
        let viewModel = PayeeEditorViewModel()
        viewModel.name = "Starbucks"
        XCTAssertNil(viewModel.logoURL)

        viewModel.logoText = "assets/logo.png"
        XCTAssertNil(viewModel.logoURL, "`startsWith('http')`")

        viewModel.logoText = "https://example.com/logo.png"
        XCTAssertEqual(viewModel.logoURL?.absoluteString, "https://example.com/logo.png")
        XCTAssertEqual(viewModel.initial, "S")
    }

    func testGroupEditorPrefillsForEditing() {
        let group = TransactionGroup(
            id: "g1", name: "Europe", description: "Trip", userId: user, priority: 1, syncStatus: 0
        )
        let viewModel = GroupEditorViewModel(target: .edit(group))
        XCTAssertTrue(viewModel.isEditing)
        XCTAssertEqual(viewModel.title, "Edit Group")
        XCTAssertEqual(viewModel.saveButtonTitle, "Save Changes")
        XCTAssertEqual(viewModel.name, "Europe")
        XCTAssertEqual(viewModel.descriptionText, "Trip")

        let fresh = GroupEditorViewModel(target: .new)
        XCTAssertFalse(fresh.isEditing)
        XCTAssertEqual(fresh.title, "New Group")
        XCTAssertEqual(fresh.saveButtonTitle, "Save Group")
    }

    func testTemplateEditorPrefillsAndLabels() {
        let subject = QuickTransaction(
            id: "q1", name: "Coffee", type: "Income", amount: 120, categoryId: nil,
            payeeId: nil, description: "brew", userId: user, productLink: "https://x",
            priority: 1, identifier: "CO", syncStatus: 0, deleted: 0
        )
        let viewModel = QuickTransactionEditorViewModel(target: .edit(subject))
        XCTAssertTrue(viewModel.isEditing)
        XCTAssertEqual(viewModel.title, "Edit Template")
        XCTAssertEqual(viewModel.saveButtonTitle, "Save Changes")
        XCTAssertEqual(viewModel.kind, .income)
        XCTAssertEqual(viewModel.amountText, "120")
        XCTAssertEqual(viewModel.identifier, "CO")
    }

    /// The amount is optional, but a present one must pass `validateAmount` — so a
    /// typed `0` is an error even though an empty field is fine.
    func testTemplateEditorValidatesTheAmountOnlyWhenPresent() async {
        let viewModel = QuickTransactionEditorViewModel(target: .new)
        viewModel.name = "Coffee"

        viewModel.amountText = ""
        var saved = await viewModel.save(pool: nil, userId: user)
        XCTAssertFalse(saved)
        XCTAssertNil(viewModel.nameError)
        XCTAssertNil(viewModel.amountError, "an empty amount means 'flexible'")

        viewModel.amountText = "0"
        saved = await viewModel.save(pool: nil, userId: user)
        XCTAssertFalse(saved)
        XCTAssertEqual(viewModel.amountError, "Amount must be greater than 0")

        viewModel.amountText = "120"
        saved = await viewModel.save(pool: nil, userId: user)
        XCTAssertFalse(saved, "no pool")
        XCTAssertNil(viewModel.amountError)
    }

    func testTemplateEditorRequiresAName() async {
        let viewModel = QuickTransactionEditorViewModel(target: .new)
        let saved = await viewModel.save(pool: nil, userId: user)
        XCTAssertFalse(saved)
        XCTAssertEqual(viewModel.nameError, "Please enter a name for this template")
    }

    // MARK: - Initial-sync guards

    func testFirstOpenGuardsAllUseTheSharedPredicate() {
        XCTAssertTrue(
            CategoriesViewModel.shouldRunInitialSync(
                categoryCount: 0, lastSyncTimestamp: nil, alreadyChecked: nil
            )
        )
        XCTAssertFalse(
            PayeesViewModel.shouldRunInitialSync(
                payeeCount: 3, lastSyncTimestamp: "2026-09-01T00:00:00.000Z",
                alreadyChecked: "1"
            )
        )
        XCTAssertTrue(
            GroupsViewModel.shouldRunInitialSync(
                groupCount: 3, lastSyncTimestamp: "not-a-timestamp", alreadyChecked: "1"
            ),
            "an invalid timestamp overrides the checked flag"
        )
        // An empty list does not by itself force a sync: the outer condition is met,
        // but the inner one still requires *never checked* or a bad timestamp.
        XCTAssertFalse(
            QuickTransactionsViewModel.shouldRunInitialSync(
                templateCount: 0, lastSyncTimestamp: "2026-09-01T00:00:00.000Z",
                alreadyChecked: "1"
            )
        )
        XCTAssertTrue(
            QuickTransactionsViewModel.shouldRunInitialSync(
                templateCount: 0, lastSyncTimestamp: "2026-09-01T00:00:00.000Z",
                alreadyChecked: nil
            )
        )
    }

    // MARK: - View models

    func testCategoryViewModelDefaults() {
        let viewModel = CategoriesViewModel()
        XCTAssertEqual(viewModel.activeTab, .expense)
        XCTAssertEqual(viewModel.sortBy, .priority)
        XCTAssertTrue(viewModel.ascending)
        XCTAssertEqual(viewModel.sortCaption, "Sorted by Priority")
        XCTAssertEqual(viewModel.viewMode, .grid)
        XCTAssertFalse(viewModel.isReordering)
        XCTAssertTrue(viewModel.canReorder)
        XCTAssertTrue(viewModel.showsSortControl)
        XCTAssertEqual(viewModel.emptyTitle, "No Expense Categories")
    }

    /// The RN screen disables the reorder toggle while searching and hides the
    /// sort/view controls while reordering.
    func testCategoryViewModelControlVisibility() {
        let viewModel = CategoriesViewModel()
        viewModel.setSearch("food")
        XCTAssertFalse(viewModel.canReorder)
        XCTAssertEqual(viewModel.emptyTitle, "No Categories Found")

        viewModel.toggleReordering(userId: nil)
        XCTAssertTrue(viewModel.isReordering)
        XCTAssertFalse(viewModel.showsSortControl)
        XCTAssertFalse(viewModel.showsViewModeControl)
    }

    func testTogglingReorderModeForcesTheListLayout() {
        let viewModel = PayeesViewModel()
        XCTAssertEqual(viewModel.viewMode, .grid)

        viewModel.toggleReordering(userId: nil)
        XCTAssertTrue(viewModel.isReordering)
        XCTAssertEqual(viewModel.viewMode, .list, "reordering needs the list layout")

        viewModel.toggleViewMode(userId: nil)
        XCTAssertEqual(viewModel.viewMode, .grid)

        viewModel.toggleReordering(userId: nil)
        XCTAssertFalse(viewModel.isReordering)
        XCTAssertEqual(viewModel.viewMode, .grid, "leaving reorder mode does not force anything")
    }

    func testTemplateViewModelHasNoSortAndDefaultsToCards() {
        let viewModel = QuickTransactionsViewModel()
        XCTAssertEqual(viewModel.viewMode, .card)
        XCTAssertFalse(viewModel.isReordering)
        XCTAssertEqual(viewModel.emptyTitle, "No Templates Yet")

        viewModel.toggleReordering(userId: nil)
        XCTAssertEqual(viewModel.viewMode, .list)
        XCTAssertFalse(viewModel.showsViewModeControl)
    }

    func testGroupsViewModelSurfacesMemberCounts() {
        let viewModel = GroupsViewModel()
        let group = TransactionGroup(
            id: "g1", name: "Europe", description: nil, userId: user, priority: 1, syncStatus: 0
        )
        XCTAssertEqual(viewModel.memberCount(for: group), 0, "no snapshot loaded yet")
    }
}
