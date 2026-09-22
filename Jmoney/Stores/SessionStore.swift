import Foundation
import Observation

/// Holds the signed-in user's session state.
///
/// Replaces the Phase 4 mock. The public surface is deliberately unchanged —
/// `isAuthenticated` / `userEmail` / `userId` / `signOut()` — because the shell,
/// every per-user query, the status bar and Settings all read those. What changed
/// is what backs them: a real Supabase session whose tokens live in the Keychain.
///
/// Reproduces `src/store/AuthContext.tsx`, including its **7-second guard**: the
/// source forces `loading = false` after 7 s so the splash screen can never hang
/// on a stalled session restore. Here the same deadline bounds `restore()`, so a
/// slow network leaves the app signed out at the gate rather than frozen.
@Observable
final class SessionStore {
    private(set) var isAuthenticated = false
    private(set) var userEmail: String?
    private(set) var userId: String?

    /// `AuthContext`'s `loading` — true until the first restore attempt settles.
    private(set) var isRestoring = true
    private(set) var isSigningIn = false

    /// Why the last sign-in failed, for the auth gate. The source shows a toast.
    var errorMessage: String?

    /// Set when the build has no Supabase configuration, so the gate can say so
    /// up front instead of failing on submit.
    let configurationMessage: String?

    private let auth: any AuthProviding
    private let restoreTimeout: Duration

    init(
        auth: any AuthProviding,
        configurationMessage: String? = nil,
        restoreTimeout: Duration = .seconds(7)
    ) {
        self.auth = auth
        self.configurationMessage = configurationMessage
        self.restoreTimeout = restoreTimeout
    }

    /// A store with no cloud auth behind it: always signed out, and signing in
    /// fails with the configuration reason.
    ///
    /// Exists for previews and the view-rendering tests, which only need the gate
    /// to draw. The app itself always injects the service `CloudFactory` resolved.
    convenience init(configurationMessage: String? = nil) {
        self.init(
            auth: UnconfiguredAuthService(unavailable: .notConfigured),
            configurationMessage: configurationMessage
        )
    }

    // MARK: - Restore

    /// `supabase.auth.getSession()` behind the source's timeout.
    func restore() async {
        isRestoring = true
        defer { isRestoring = false }

        let auth = self.auth
        let user = await withRestoreTimeout { await auth.restoreSession() }
        apply(user)
    }

    /// `onAuthStateChange` — keeps the shell in step with token refreshes and
    /// sign-outs that happen outside this object.
    func observeSessionChanges() async {
        for await user in auth.sessionChanges() {
            apply(user)
        }
    }

    private func withRestoreTimeout(
        _ operation: @escaping @Sendable () async -> AuthUser?
    ) async -> AuthUser? {
        await withTaskGroup(of: AuthUser?.self) { group in
            group.addTask { await operation() }
            group.addTask { [restoreTimeout] in
                try? await Task.sleep(for: restoreTimeout)
                return nil
            }
            // Whichever finishes first wins; the timeout yields `nil`, i.e.
            // "signed out", which is the source's forced-loading-off state.
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Sign in / out

    /// `signInWithPassword`. Returns whether it succeeded; `errorMessage` carries
    /// the reason when it did not.
    @discardableResult
    func signIn(email: String, password: String) async -> Bool {
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let user = try await auth.signIn(email: email, password: password)
            apply(user)
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// `supabase.auth.signOut()`. Local data is deliberately kept, matching the
    /// source: signing out is not a data reset.
    func signOut() {
        Task { [auth] in
            try? await auth.signOut()
        }
        apply(nil)
    }

    private func apply(_ user: AuthUser?) {
        isAuthenticated = user != nil
        userEmail = user?.email
        userId = user?.id
    }
}
