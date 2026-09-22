import Foundation
import Supabase

/// The cloud half of the app, resolved once at launch.
///
/// An unconfigured build (no Supabase credentials in the xcconfig) is a supported
/// state: `config` is `nil`, `unavailable` explains why, and the auth and sync
/// services are replaced by honest stubs that refuse cloud work rather than
/// crashing or pretending to succeed.
struct CloudServices {
    var config: SupabaseConfig?
    var unavailable: SupabaseConfig.Unavailable?
    var auth: any AuthProviding
    var sync: SyncService
    /// The client the app shares, when configured.
    var client: SupabaseClient?

    var isConfigured: Bool { config != nil }
}

enum CloudFactory {
    /// `SupabaseClient` with Keychain session storage and token auto-refresh.
    ///
    /// `emitLocalSessionAsInitialSession` is enabled so a stored session counts
    /// immediately at launch instead of waiting on a refresh round-trip — the
    /// source's `getSession()` is likewise local-first, and the shell's 7-second
    /// restore timeout should not be spent on the network.
    static func makeClient(config: SupabaseConfig) -> SupabaseClient {
        SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: KeychainAuthStorage(),
                    autoRefreshToken: true,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    /// Resolves the build configuration and assembles the services.
    static func make(
        bundle: Bundle = .main,
        connectivity: any ConnectivityProviding = ConnectivityMonitor(),
        defaults: UserDefaults = .standard
    ) -> CloudServices {
        switch SupabaseConfig.resolve(bundle: bundle) {
        case .success(let config):
            let client = makeClient(config: config)
            return CloudServices(
                config: config,
                unavailable: nil,
                auth: SupabaseAuthService(client: client),
                sync: SyncService(
                    backend: SupabaseSyncBackend(client: client),
                    connectivity: connectivity,
                    defaults: defaults
                ),
                client: client
            )
        case .failure(let unavailable):
            return CloudServices(
                config: nil,
                unavailable: unavailable,
                auth: UnconfiguredAuthService(unavailable: unavailable),
                sync: SyncService(
                    backend: UnconfiguredSyncBackend(unavailable: unavailable),
                    connectivity: connectivity,
                    defaults: defaults
                ),
                client: nil
            )
        }
    }
}

/// Auth that always reports "signed out" and refuses to sign in.
///
/// Deliberately not a silent no-op: signing in has to fail loudly, because the
/// user's alternative explanation is a wrong password.
struct UnconfiguredAuthService: AuthProviding {
    let unavailable: SupabaseConfig.Unavailable

    func restoreSession() async -> AuthUser? { nil }

    func signIn(email: String, password: String) async throws -> AuthUser {
        throw AuthError.notConfigured(unavailable.message)
    }

    func signOut() async throws {}

    func sessionChanges() -> AsyncStream<AuthUser?> {
        AsyncStream { $0.finish() }
    }
}

/// A backend that fails every call with the configuration reason, so a sync
/// attempt on an unconfigured build reports exactly why instead of appearing to
/// work.
struct UnconfiguredSyncBackend: SyncBackend {
    let unavailable: SupabaseConfig.Unavailable

    private func fail() throws -> Never {
        throw SyncError.notConfigured(unavailable)
    }

    func fetchAll(table: String, userId: String) async throws -> [RemoteRecord] { try fail() }
    func fetchTransactions(
        userId: String, tidGreaterThan: Int, range: ClosedRange<Int>
    ) async throws -> [RemoteRecord] { try fail() }
    func maxTransactionTid(userId: String) async throws -> Int? { try fail() }
    func upsert(table: String, records: [RemoteRecord]) async throws { try fail() }
    func upsertReturningTid(table: String, record: RemoteRecord) async throws -> Int? { try fail() }
    func delete(table: String, id: String) async throws { try fail() }
}
