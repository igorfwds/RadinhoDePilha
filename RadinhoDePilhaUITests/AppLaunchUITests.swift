import XCTest

/// Smoke test for app launch.
///
/// XCTest rather than Swift Testing because UI automation has no Swift Testing equivalent:
/// `XCUIApplication` and everything around it live only in XCTest. Unit tests in this project are
/// all Swift Testing; XCTest appears here and nowhere else.
///
/// Marked `nonisolated` because `XCTestCase` and its overridable members are not actor-isolated,
/// while the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION` set to `MainActor`. Without it,
/// every override conflicts with the superclass declaration.
nonisolated final class AppLaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertEqual(app.state, .runningForeground)
    }
}
