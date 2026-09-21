import Observation

/// Holds the signed-in user's session state.
///
/// Phase 4 placeholder: a mock session flipped by the auth gate so the shell can
/// be exercised end-to-end. Phase 14 replaces this with a real Supabase session
/// persisted to the Keychain (see DATA_ARCHITECTURE.md §3.5). Sign-out keeps
/// local data on disk, matching the React Native app's behavior.
@Observable
final class SessionStore {
    private(set) var isAuthenticated = false
    private(set) var userEmail: String?

    /// The Supabase user id the local tables are scoped by (`user_id`). Phase 14
    /// fills this from the restored session; until then the mock id below keeps
    /// the per-user queries exercised with a stable value.
    private(set) var userId: String?

    /// Stand-in for `session.user.id` while the auth gate is mocked.
    static let placeholderUserId = "00000000-0000-0000-0000-000000000001"

    /// Mock sign-in used by the placeholder auth gate.
    func signInPlaceholder(email: String) {
        userEmail = email
        userId = Self.placeholderUserId
        isAuthenticated = true
    }

    func signOut() {
        isAuthenticated = false
        userEmail = nil
        userId = nil
    }
}
