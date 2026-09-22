import SwiftUI
import XCTest

@testable import Jmoney

/// Renders the Phase 13 settings surfaces so a crash or an un-layoutable
/// combination fails the suite rather than the user.
///
/// `ImageRenderer` evaluates the view bodies and runs SwiftUI layout. `task` does
/// not run, and no action is dispatched, so this is the opened-but-untouched
/// state: no LocalAuthentication prompt, no notification request.
@MainActor
final class SettingsViewRenderingTests: XCTestCase {
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
            .environment(AppearanceStore())
    }

    // MARK: - Surfaces

    func testSettingsViewRenders() throws {
        try assertRenders(
            environment(SettingsView()).frame(width: 640, height: 720),
            named: "Settings"
        )
    }

    func testSettingsPaneRenders() throws {
        try assertRenders(
            environment(SettingsPaneView()).frame(width: 900, height: 700),
            named: "Settings pane"
        )
    }

    func testSettingsSceneRenders() throws {
        try assertRenders(
            environment(SettingsSceneView()).frame(width: 480, height: 620),
            named: "Settings scene"
        )
    }

    // MARK: - Reminder chooser

    func testReminderChooserRendersForEachNamedSelection() throws {
        for preference in [
            ReminderPreference.none, .morning, .evening, .night,
        ] {
            try assertRenders(
                ReminderChooserSheet(current: preference) { _ in },
                named: "Reminder chooser (\(preference))"
            )
        }
    }

    func testReminderChooserRendersWithTheCustomEditorExpanded() throws {
        // A stored custom time opens the sheet with the inline time field showing.
        try assertRenders(
            ReminderChooserSheet(current: .custom("07:30")) { _ in },
            named: "Reminder chooser (custom)"
        )
    }

    func testReminderChooserHandlesAnUnparseableStoredValue() throws {
        // A value with no colon is shown as "Custom (…)" but is *not* marked
        // selected, and the pane stays collapsed — the source's quirk.
        try assertRenders(
            ReminderChooserSheet(current: .custom("Afternoon")) { _ in },
            named: "Reminder chooser (unparseable)"
        )
    }

    // MARK: - Rows

    func testSettingsRowsRenderInBothTones() throws {
        try assertRenders(
            SettingsRow(systemImage: "trash", title: "Reset Data", detail: "Wipe all local records", tone: .destructive) {},
            named: "Destructive row"
        )
        try assertRenders(
            SettingsRow(systemImage: "flag", title: "Goals", detail: "Manage Savings Goals") {},
            named: "Normal row"
        )
        try assertRenders(
            SettingsRowLabel(systemImage: "hand.tap", title: "Haptic Feedback", detail: "Not available on Mac — no haptics hardware"),
            named: "Row label without detail"
        )
    }

    func testSettingsRowRendersWithoutADetail() throws {
        try assertRenders(
            SettingsRow(systemImage: "person", title: "Sign Out") {},
            named: "Row without detail"
        )
    }

    // MARK: - Derived state the view reads

    func testAppearancePickerOptionsAreAllRenderable() throws {
        for preference in AppearancePreference.allCases {
            try assertRenders(
                Label(preference.title, systemImage: preference.systemImage),
                named: "Appearance option (\(preference.title))"
            )
        }
    }
}
