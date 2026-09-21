import SwiftUI
import XCTest

@testable import Jmoney

/// Renders the dashboard so a crash or an un-layoutable widget combination in the
/// zero-value (empty database) state fails the suite rather than the user.
///
/// `ImageRenderer` evaluates the view bodies and runs SwiftUI layout. `.task` does
/// not run, so this is exactly the first-launch state: metrics at their defaults,
/// no session, no open pool.
@MainActor
final class DashboardViewRenderingTests: XCTestCase {
    func testDashboardRendersInItsZeroValueState() throws {
        let view = DashboardView()
            .environment(AppState())
            .environment(SessionStore())
            .environment(DatabaseService())
            .frame(width: 900, height: 700)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.nsImage, "Dashboard failed to render")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testTodaysActivityRendersItsEmptyState() throws {
        let view = TodaysActivityView(pool: nil, userId: nil)
            .frame(width: 520, height: 480)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.nsImage, "Today's Activity failed to render")
        XCTAssertGreaterThan(image.size.width, 0)
    }

    func testDashboardViewModelDefaultsMatchTheZeroMetrics() {
        let viewModel = DashboardViewModel()
        XCTAssertEqual(viewModel.metrics, DashboardService.Metrics())
        XCTAssertEqual(viewModel.dailyLimit.limit, 0)
        XCTAssertEqual(viewModel.dailyLimit.remainingPercentage, 100)
        XCTAssertEqual(viewModel.payDayInfo.remaining, viewModel.payDayInfo.daysInMonth - viewModel.payDayInfo.currentDay + 1)
    }
}
