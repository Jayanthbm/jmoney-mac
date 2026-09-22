import Foundation
import Supabase

/// `AuthProviding` on top of supabase-swift's `AuthClient`.
///
/// Replaces `src/store/AuthContext.tsx` + the `AsyncStorage` session storage in
/// `src/services/supabase.ts`. The session itself lives in the Keychain
/// (`KeychainAuthStorage`), which the client is configured with in
/// `SupabaseClientFactory`; token refresh is the SDK's job and is left enabled.
struct SupabaseAuthService: AuthProviding {
    let client: SupabaseClient

    func restoreSession() async -> AuthUser? {
        do {
            // `auth.session` refreshes an expired token before returning.
            return Self.user(from: try await client.auth.session)
        } catch {
            // No stored session (`AuthError.sessionMissing`) is the signed-out
            // case; the source's `getSession()` also resolves to null there.
            return nil
        }
    }

    func signIn(email: String, password: String) async throws -> AuthUser {
        do {
            return Self.user(from: try await client.auth.signIn(email: email, password: password))
        } catch {
            throw AuthError.failed(Self.message(for: error))
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            throw AuthError.failed(Self.message(for: error))
        }
    }

    func sessionChanges() -> AsyncStream<AuthUser?> {
        let changes = client.auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await change in changes {
                    continuation.yield(change.session.map(Self.user(from:)))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `session.user.id.uuidString` **lowercased** — see `AuthUser.id`.
    static func user(from session: Session) -> AuthUser {
        AuthUser(id: session.user.id.uuidString.lowercased(), email: session.user.email)
    }

    private static func message(for error: Error) -> String {
        let text = error.localizedDescription
        return text.isEmpty ? "Authentication failed." : text
    }
}
