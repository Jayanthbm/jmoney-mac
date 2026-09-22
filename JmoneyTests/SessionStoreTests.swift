import GRDB
import XCTest

@testable import Jmoney

/// Verifies the auth shell: session restore (including the source's 7-second
/// guard), sign-in/sign-out, and the honest failure path on a build with no
/// Supabase configuration.
final class SessionStoreTests: XCTestCase {
    /// A scriptable `AuthProviding`. `@unchecked Sendable` because `signOut` is
    /// performed in a detached task, exactly as the real store does it.
    final class FakeAuthService: AuthProviding, @unchecked Sendable {
        var restored: AuthUser?
        var restoreDelay: Duration?
        var signInResult: Result<AuthUser, Error>
        private(set) var signOutCount = 0
        private(set) var signInEmails: [String] = []
        private(set) var restoreCount = 0

        /// Driven by the tests to emulate an external sign-out or a token refresh.
        private var continuation: AsyncStream<AuthUser?>.Continuation?

        init(
            restored: AuthUser? = nil,
            restoreDelay: Duration? = nil,
            signInResult: Result<AuthUser, Error> = .failure(AuthError.failed("nope"))
        ) {
            self.restored = restored
            self.restoreDelay = restoreDelay
            self.signInResult = signInResult
        }

        func restoreSession() async -> AuthUser? {
            restoreCount += 1
            if let restoreDelay { try? await Task.sleep(for: restoreDelay) }
            return restored
        }

        func signIn(email: String, password: String) async throws -> AuthUser {
            signInEmails.append(email)
            return try signInResult.get()
        }

        func signOut() async throws {
            signOutCount += 1
        }

        func sessionChanges() -> AsyncStream<AuthUser?> {
            AsyncStream { continuation in
                self.continuation = continuation
            }
        }

        /// True once someone is actually iterating `sessionChanges()`. Yielding
        /// before that would go nowhere, so the tests wait on it.
        var isSubscribed: Bool { continuation != nil }

        func emit(_ user: AuthUser?) {
            continuation?.yield(user)
        }
    }

    private let user = AuthUser(id: "3f1a0c58-0f4e-4a0e-9d1c-2b3a4c5d6e7f", email: "jay@example.com")

    /// Polls a condition with a deadline, so assertions about work done in a
    /// detached task are not timing-dependent.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Restore

    func testRestoreAppliesAStoredSession() async {
        let store = SessionStore(auth: FakeAuthService(restored: user))

        await store.restore()

        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(store.userId, user.id)
        XCTAssertEqual(store.userEmail, "jay@example.com")
        XCTAssertFalse(store.isRestoring)
    }

    func testRestoreWithoutASessionIsSignedOutNotAnError() async {
        let store = SessionStore(auth: FakeAuthService(restored: nil))

        await store.restore()

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(store.userId)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isRestoring)
    }

    func testASlowRestoreTimesOutIntoSignedOut() async {
        // The source forces `loading = false` after 7 s; the injected timeout is
        // the same guard, and a stalled restore must leave the gate usable.
        let auth = FakeAuthService(restored: user, restoreDelay: .seconds(30))
        let store = SessionStore(auth: auth, restoreTimeout: .milliseconds(50))

        let started = Date()
        await store.restore()

        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertFalse(store.isAuthenticated)
        XCTAssertFalse(store.isRestoring)
    }

    func testARestoreInsideTheDeadlineSucceeds() async {
        let auth = FakeAuthService(restored: user, restoreDelay: .milliseconds(10))
        let store = SessionStore(auth: auth, restoreTimeout: .seconds(5))

        await store.restore()

        XCTAssertTrue(store.isAuthenticated)
    }

    // MARK: - Sign in

    func testSignInAppliesTheUserAndClearsAPreviousError() async {
        let auth = FakeAuthService(signInResult: .success(user))
        let store = SessionStore(auth: auth)
        store.errorMessage = "stale"

        let signedIn = await store.signIn(email: "jay@example.com", password: "secret")

        XCTAssertTrue(signedIn)
        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(store.userId, user.id)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isSigningIn)
        XCTAssertEqual(auth.signInEmails, ["jay@example.com"])
    }

    func testSignInFailureSurfacesTheReasonAndStaysSignedOut() async {
        let store = SessionStore(
            auth: FakeAuthService(signInResult: .failure(AuthError.failed("Invalid credentials")))
        )

        let signedIn = await store.signIn(email: "jay@example.com", password: "wrong")

        XCTAssertFalse(signedIn)
        XCTAssertFalse(store.isAuthenticated)
        XCTAssertEqual(store.errorMessage, "Invalid credentials")
        XCTAssertFalse(store.isSigningIn)
    }

    // MARK: - Sign out

    func testSignOutClearsTheShellAndTellsTheService() async {
        let auth = FakeAuthService(restored: user)
        let store = SessionStore(auth: auth)
        await store.restore()
        XCTAssertTrue(store.isAuthenticated)

        store.signOut()

        // The state clears synchronously; the remote call happens off to the side.
        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(store.userId)
        XCTAssertNil(store.userEmail)

        await waitUntil { auth.signOutCount == 1 }
        XCTAssertEqual(auth.signOutCount, 1)
    }

    // MARK: - External session changes

    func testAnExternalSignOutIsReflected() async {
        let auth = FakeAuthService(restored: user)
        let store = SessionStore(auth: auth)
        await store.restore()

        let observing = Task { await store.observeSessionChanges() }
        defer { observing.cancel() }
        await waitUntil { auth.isSubscribed }

        auth.emit(nil)

        await waitUntil { !store.isAuthenticated }
        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(store.userEmail)
    }

    func testAnExternalTokenRefreshUpdatesTheEmail() async {
        let auth = FakeAuthService(restored: user)
        let store = SessionStore(auth: auth)
        await store.restore()

        let observing = Task { await store.observeSessionChanges() }
        defer { observing.cancel() }
        await waitUntil { auth.isSubscribed }

        let refreshed = AuthUser(id: user.id, email: "new@example.com")
        auth.emit(refreshed)

        await waitUntil { store.userEmail == "new@example.com" }
        XCTAssertEqual(store.userEmail, "new@example.com")
    }

    // MARK: - The unconfigured build

    func testTheConvenienceStoreIsSignedOutAndSaysWhy() async {
        let store = SessionStore(configurationMessage: "no Supabase project")

        await store.restore()
        XCTAssertFalse(store.isAuthenticated)
        XCTAssertEqual(store.configurationMessage, "no Supabase project")

        let signedIn = await store.signIn(email: "jay@example.com", password: "x")
        XCTAssertFalse(signedIn)
        // Signing in has to fail loudly: the alternative explanation the user
        // reaches for is a wrong password.
        XCTAssertNotNil(store.errorMessage)
    }

    func testUnconfiguredBuildSyncFailsAndLeavesTheAccountUnsynced() async throws {
        let dbQueue = try DatabaseQueue()
        try DatabaseService.migrator.migrate(dbQueue)

        let suiteName = "SessionStoreTests.unconfigured.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = SyncService(
            backend: UnconfiguredSyncBackend(unavailable: .notConfigured),
            connectivity: AlwaysOnlineConnectivity(),
            defaults: defaults
        )

        let outcome = await service.runFullSync(userId: user.id, writer: dbQueue)

        guard case .failed(let message) = outcome else {
            return XCTFail("expected a failure, got \(outcome)")
        }
        XCTAssertTrue(message.contains("no Supabase"))
        XCTAssertNil(SyncPreference.lastFullSync(userId: user.id, defaults: defaults))
    }

    func testUnconfiguredAuthRefusesRestoreAndSignIn() async {
        let auth = UnconfiguredAuthService(unavailable: .invalidURL("bogus"))

        let restored = await auth.restoreSession()
        XCTAssertNil(restored)

        do {
            _ = try await auth.signIn(email: "a@b.c", password: "x")
            XCTFail("expected a configuration failure")
        } catch let error as AuthError {
            XCTAssertTrue(error.errorDescription?.contains("bogus") ?? false)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testCloudFactoryReportsTheConfigurationProblem() {
        // A bare bundle has no `JMoneySupabaseURL`, which is the state of a fresh
        // checkout — assembling the services must still succeed.
        let services = CloudFactory.make(bundle: Bundle(for: SessionStoreTests.self))

        XCTAssertFalse(services.isConfigured)
        XCTAssertNil(services.config)
        XCTAssertNil(services.client)
        XCTAssertNotNil(services.unavailable)
    }
}
