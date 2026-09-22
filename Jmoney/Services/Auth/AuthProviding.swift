import Foundation

/// The signed-in identity.
///
/// `id` is the Supabase user id **as a lowercase string**, which is what
/// supabase-js puts in `session.user.id` and therefore what every `user_id`
/// column in the React Native database already holds. `UUID.uuidString` is
/// uppercase, so the conversion has to lowercase explicitly or the macOS app
/// would scope every query to a user id that never matches its own data.
struct AuthUser: Equatable, Sendable {
    var id: String
    var email: String?
}

/// Authentication, as the shell needs it.
///
/// A protocol so `SessionStore` — and through it the auth gate — can be tested
/// without a Supabase project. The only production implementation is
/// `SupabaseAuthService`.
protocol AuthProviding: Sendable {
    /// The persisted session, if there is a usable one. `nil` means "signed out",
    /// which is a normal state rather than an error.
    func restoreSession() async -> AuthUser?

    /// `signInWithPassword` — throws on bad credentials or a network failure.
    func signIn(email: String, password: String) async throws -> AuthUser

    /// Clears the session. Local data is untouched, as in the source.
    func signOut() async throws

    /// Emits on every auth state change, so a token refresh or an external
    /// sign-out updates the shell.
    func sessionChanges() -> AsyncStream<AuthUser?>
}

/// `useBiometrics`-style capability errors are separate; these are the auth ones.
enum AuthError: LocalizedError, Equatable {
    case notConfigured(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message): return message
        case .failed(let message): return message
        }
    }
}
