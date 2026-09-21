import SwiftUI
import XCTest

@testable import Jmoney

/// Renders the Phase 12 screens, rows and editors so a crash or an un-layoutable
/// combination in the zero state fails the suite rather than the user.
///
/// `ImageRenderer` evaluates the view bodies and runs SwiftUI layout. `.task` does
/// not run, so this is the first-launch state: no rows, no session, no open pool.
@MainActor
final class ManagementViewsRenderingTests: XCTestCase {
    private func category() -> Jmoney.Category {
        Jmoney.Category(
            id: "c1", name: "Groceries", type: "Expense", icon: "", appIcon: "fastfood",
            userId: "u1", isLivingCost: 0, syncStatus: 0, priority: 1
        )
    }

    private func payee() -> Payee {
        Payee(
            id: "p1", name: "Starbucks", logo: "https://example.com/logo.png", userId: "u1",
            syncStatus: 0, priority: 1
        )
    }

    private func group() -> TransactionGroup {
        TransactionGroup(
            id: "g1", name: "Europe Trip", description: "Summer 2026", userId: "u1", priority: 1,
            syncStatus: 0
        )
    }

    private func template(amount: Double? = 120) -> QuickTransaction {
        QuickTransaction(
            id: "q1", name: "Morning Coffee", type: "Expense", amount: amount, categoryId: "c1",
            payeeId: nil, description: "brew", userId: "u1", productLink: nil, priority: 1,
            identifier: "CO", syncStatus: 0, deleted: 0
        )
    }

    private func assertRenders(_ view: some View, named name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage, "\(name) failed to render")
        XCTAssertGreaterThan(image.size.width, 0, name)
        XCTAssertGreaterThan(image.size.height, 0, name)
    }

    private func environment<V: View>(_ view: V) -> some View {
        view
            .environment(AppState())
            .environment(SessionStore())
            .environment(DatabaseService())
    }

    // MARK: - Screens

    func testCategoriesRendersInItsZeroValueState() throws {
        try assertRenders(
            environment(CategoriesView()).frame(width: 900, height: 700),
            named: "Categories"
        )
    }

    func testPayeesRendersInItsZeroValueState() throws {
        try assertRenders(
            environment(PayeesView()).frame(width: 900, height: 700),
            named: "Payees"
        )
    }

    func testGroupsRendersInItsZeroValueState() throws {
        try assertRenders(
            environment(GroupsView()).frame(width: 900, height: 700),
            named: "Groups"
        )
    }

    func testQuickTransactionsRendersInItsZeroValueState() throws {
        try assertRenders(
            environment(QuickTransactionsView()).frame(width: 900, height: 700),
            named: "Quick Transactions"
        )
    }

    // MARK: - Editors

    func testCategoryEditorAndIconPickerRender() throws {
        try assertRenders(
            environment(CategoryEditorView()).frame(width: 460, height: 560),
            named: "Category editor"
        )
    }

    func testPayeeEditorRenders() throws {
        try assertRenders(
            environment(PayeeEditorView()).frame(width: 440, height: 420),
            named: "Payee editor"
        )
    }

    func testGroupEditorsRenderForNewAndExisting() throws {
        try assertRenders(
            environment(GroupEditorView(target: .new) { _ in }).frame(width: 460, height: 400),
            named: "Group editor (new)"
        )
        try assertRenders(
            environment(GroupEditorView(target: .edit(group())) { _ in })
                .frame(width: 460, height: 400),
            named: "Group editor (edit)"
        )
    }

    func testTemplateEditorsRenderForNewAndExisting() throws {
        try assertRenders(
            environment(QuickTransactionEditorView(target: .new)).frame(width: 520, height: 560),
            named: "Template editor (new)"
        )
        try assertRenders(
            environment(QuickTransactionEditorView(target: .edit(template())))
                .frame(width: 520, height: 560),
            named: "Template editor (edit)"
        )
    }

    func testQuickTransactionPickerSheetRenders() throws {
        try assertRenders(
            environment(QuickTransactionPickerSheet()).frame(width: 520, height: 380),
            named: "Quick transaction picker"
        )
    }

    // MARK: - Rows

    func testCategoryRowsRenderInBothLayouts() throws {
        for mode: ViewModePreference.ListGridMode in [.list, .grid] {
            try assertRenders(
                CategoryRow(category: category(), viewMode: mode).frame(width: 300),
                named: "Category row (\(mode.rawValue))"
            )
        }
    }

    func testPayeeRowsRenderInBothLayouts() throws {
        for mode: ViewModePreference.ListGridMode in [.list, .grid] {
            try assertRenders(
                PayeeRow(payee: payee(), viewMode: mode).frame(width: 300),
                named: "Payee row (\(mode.rawValue))"
            )
        }
    }

    func testGroupRowsRenderWithAndWithoutADescription() throws {
        let withoutDescription = TransactionGroup(
            id: "g2", name: "Home", description: nil, userId: "u1", priority: 2, syncStatus: 0
        )
        for subject in [group(), withoutDescription] {
            try assertRenders(
                GroupRow(group: subject, viewMode: .list).frame(width: 300),
                named: "Group row (\(subject.id))"
            )
            try assertRenders(
                GroupRow(group: subject, viewMode: .grid).frame(width: 300),
                named: "Group card (\(subject.id))"
            )
        }
    }

    /// The card shows a delete affordance only when one is supplied, and the amount
    /// is either a formatted value or the literal "Flexible".
    func testTemplateRowsRenderWithAndWithoutADeleteAction() throws {
        try assertRenders(
            QuickTransactionRow(template: template(), style: .card, onDelete: nil).frame(width: 240),
            named: "Template card"
        )
        try assertRenders(
            QuickTransactionRow(template: template(amount: nil), style: .card, onDelete: {}).frame(width: 240),
            named: "Flexible template card"
        )
        try assertRenders(
            QuickTransactionRow(template: template(), style: .list, onDelete: {}).frame(width: 420),
            named: "Template list row"
        )
    }

    // MARK: - Icon picker

    func testIconPickerRendersWithAndWithoutAName() throws {
        let unmapped = CategoryIconPicker(materialName: .constant("not-a-real-icon"))
            .frame(width: 400)
        try assertRenders(unmapped, named: "Icon picker (unmapped)")

        let mapped = CategoryIconPicker(materialName: .constant("fastfood"))
            .frame(width: 400)
        try assertRenders(mapped, named: "Icon picker (mapped)")
    }
}
