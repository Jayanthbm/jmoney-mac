import Foundation
import GRDB
import Observation

/// The full-sync coordinator — a port of `src/services/syncService.ts`.
///
/// Reproduces the source's ordering, its progress strings, its re-entrancy guard
/// and its error containment: any failure aborts the run, reports `'Error'` and
/// deliberately does **not** write the master timestamp, so the next check
/// considers the account unsynced.
///
/// Dependencies are injected, so the whole flow — including the offline branch and
/// the guard — is exercised in tests against a fake backend and a fake network.
@Observable
final class SyncService {
    /// What a sync attempt did. The source reports this through `onProgress`
    /// strings and leaves the caller to infer the outcome; a typed result is the
    /// same information without string matching.
    enum Outcome: Equatable {
        case completed
        /// The connectivity check said no before anything was attempted.
        case offline
        /// Another sync was already running — the source returns silently here.
        case alreadyRunning
        case failed(String)
    }

    private let backend: any SyncBackend
    private let connectivity: any ConnectivityProviding
    private let defaults: UserDefaults
    private let now: () -> Date

    /// The module-level `isSyncingData` flag: `runFullSync` is a no-op while one is
    /// in flight, which matters because several screens can trigger a sync.
    private(set) var isSyncing = false

    /// The most recent progress step, which the status bar renders. Published
    /// rather than delivered through a callback so the UI never has to hand a
    /// non-Sendable closure to a background sync.
    private(set) var lastProgress: SyncProgress?

    /// Every step of the most recent run, in order. The source reports the same
    /// sequence through `onProgress`; keeping the log makes the ordering
    /// assertable rather than merely observable.
    private(set) var progressLog: [SyncProgress] = []

    private(set) var lastError: String?

    init(
        backend: any SyncBackend,
        connectivity: any ConnectivityProviding,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.backend = backend
        self.connectivity = connectivity
        self.defaults = defaults
        self.now = now
    }

    // MARK: - Push

    /// `pushLocalChanges` — every entity's dirty rows, in the source's order.
    ///
    /// Each entity's push is independent: a failure propagates and aborts the
    /// push, leaving the remaining rows dirty for the next attempt, which is the
    /// source's behaviour (its `await`s are sequential and unguarded).
    func pushLocalChanges(userId: String, writer: any DatabaseWriter) async throws {
        let timestamp = now()
        for entity in SyncEntity.pushOrder {
            try await Self.push(
                entity: entity, userId: userId, writer: writer, backend: backend, now: timestamp
            )
        }
    }

    // MARK: - Full sync

    /// `runFullSync(userId, onProgress)`.
    ///
    /// The guard is checked *before* anything else and returns without emitting
    /// progress, exactly like the source's early `if (isSyncingData) return`.
    @discardableResult
    func runFullSync(userId: String, writer: any DatabaseWriter) async -> Outcome {
        guard !isSyncing else { return .alreadyRunning }
        isSyncing = true
        progressLog = []
        defer { isSyncing = false }

        guard await connectivity.isOnline() else {
            report(.offline)
            return .offline
        }

        do {
            report(.pushingLocalChanges)
            try await pushLocalChanges(userId: userId, writer: writer)

            for entity in SyncEntity.fullSyncOrder {
                report(.entity(entity))
                try await Self.pull(
                    entity: entity, userId: userId, writer: writer, backend: backend,
                    now: now(), defaults: defaults
                )
            }

            report(.finalizing)
            SyncPreference.saveLastFullSync(now(), userId: userId, defaults: defaults)
            lastError = nil
            return .completed
        } catch {
            // The master timestamp is intentionally not written on this path, so
            // the next launch still considers the account unsynced.
            let message = (error as? SyncError)?.errorDescription ?? error.localizedDescription
            lastError = message
            report(.failed)
            return .failed(message)
        }
    }

    // MARK: - Transactions only

    /// `syncTransactions(userId, isPartial)`.
    ///
    /// - Parameter isPartial: `false` is the source's force resync (wipe local
    ///   transactions, re-pull from `tid = 0`).
    @discardableResult
    func syncTransactions(
        userId: String,
        isPartial: Bool,
        writer: any DatabaseWriter
    ) async -> Outcome {
        guard !isSyncing else { return .alreadyRunning }
        isSyncing = true
        defer { isSyncing = false }

        guard await connectivity.isOnline() else {
            lastError = SyncError.offline.errorDescription
            return .offline
        }

        do {
            try await TransactionSync.pull(
                userId: userId,
                isPartial: isPartial,
                writer: writer,
                backend: backend,
                now: now(),
                defaults: defaults
            )
            lastError = nil
            return .completed
        } catch {
            let message = (error as? SyncError)?.errorDescription ?? error.localizedDescription
            lastError = message
            return .failed(message)
        }
    }

    /// `forceTransactionsSync` — `syncTransactions(userId, false)`.
    @discardableResult
    func forceTransactionsSync(userId: String, writer: any DatabaseWriter) async -> Outcome {
        await syncTransactions(userId: userId, isPartial: false, writer: writer)
    }

    // MARK: - A single entity

    /// `syncBudgets` / `syncGoals` / `syncCategories` / `syncPayees` — the
    /// per-entity push-then-pull the four management screens run on first open.
    ///
    /// Note this is a *full replace* pull for the meta entities, not the
    /// incremental one, exactly as the source's per-entity functions are.
    @discardableResult
    func syncEntity(
        _ entity: SyncEntity,
        userId: String,
        writer: any DatabaseWriter
    ) async -> Outcome {
        guard !isSyncing else { return .alreadyRunning }
        isSyncing = true
        progressLog = []
        defer { isSyncing = false }

        guard await connectivity.isOnline() else {
            report(.offline)
            return .offline
        }

        do {
            let timestamp = now()
            report(.entity(entity))
            try await Self.push(
                entity: entity, userId: userId, writer: writer, backend: backend, now: timestamp
            )
            try await Self.pull(
                entity: entity, userId: userId, writer: writer, backend: backend,
                now: timestamp, defaults: defaults
            )
            lastError = nil
            return .completed
        } catch {
            let message = (error as? SyncError)?.errorDescription ?? error.localizedDescription
            lastError = message
            report(.failed)
            return .failed(message)
        }
    }

    // MARK: - Push only

    /// A **push-only** run for one entity — `backgroundPushCategories`,
    /// `backgroundPushPayees`, `backgroundPushGroups` and
    /// `backgroundPushQuickTransactions`, which the reorder toggles call when they
    /// are *exited*.
    ///
    /// Like those functions this is fire-and-forget: it never touches the
    /// first-open flags, never runs a pull, and failure is reported, not fatal.
    @discardableResult
    func pushEntity(
        _ entity: SyncEntity,
        userId: String,
        writer: any DatabaseWriter
    ) async -> Outcome {
        guard !isSyncing else { return .alreadyRunning }
        isSyncing = true
        defer { isSyncing = false }

        guard await connectivity.isOnline() else {
            lastError = SyncError.offline.errorDescription
            return .offline
        }

        do {
            try await Self.push(
                entity: entity, userId: userId, writer: writer, backend: backend, now: now()
            )
            lastError = nil
            return .completed
        } catch {
            let message = (error as? SyncError)?.errorDescription ?? error.localizedDescription
            lastError = message
            return .failed(message)
        }
    }

    // MARK: - The sync-needed check

    /// `needsTransactionSync` — `localMaxTid < remoteMaxTid`.
    ///
    /// Returns `false` when offline or on any backend error, so a network problem
    /// never turns into an unexpected full re-pull.
    func needsTransactionSync(userId: String, writer: any DatabaseWriter) async -> Bool {
        guard await connectivity.isOnline() else { return false }
        do {
            let localMax = try await writer.read {
                try SyncRowWriter.maxTransactionTid(userId: userId, in: $0)
            }
            let remoteMax = try await backend.maxTransactionTid(userId: userId) ?? 0
            return localMax < remoteMax
        } catch {
            lastError = (error as? SyncError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: - Dispatch

    private func report(_ progress: SyncProgress) {
        lastProgress = progress
        progressLog.append(progress)
    }

    private static func push(
        entity: SyncEntity,
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend,
        now: Date
    ) async throws {
        switch entity {
        case .transactions:
            try await TransactionSync.push(userId: userId, writer: writer, backend: backend, now: now)
        case .goals:
            try await GoalSync.push(userId: userId, writer: writer, backend: backend)
        case .budgets:
            try await BudgetSync.push(userId: userId, writer: writer, backend: backend)
        case .categories:
            try await CategorySync.push(userId: userId, writer: writer, backend: backend)
        case .payees:
            try await PayeeSync.push(userId: userId, writer: writer, backend: backend)
        case .quickTransactions:
            try await QuickTransactionSync.push(userId: userId, writer: writer, backend: backend)
        case .transactionGroups:
            try await GroupSync.push(userId: userId, writer: writer, backend: backend)
        }
    }

    /// `defaults` is threaded through to every entity's pull because each one writes
    /// its own `@last_sync_<entity>_<userId>` timestamp — the coordinator's storage
    /// is the app's, so a caller that injects storage (tests) must see those writes.
    private static func pull(
        entity: SyncEntity,
        userId: String,
        writer: any DatabaseWriter,
        backend: any SyncBackend,
        now: Date,
        defaults: UserDefaults
    ) async throws {
        switch entity {
        case .transactions:
            // `runFullSync` pulls transactions with the force flag, which is why
            // the dashboard's first sync always re-downloads the whole ledger.
            try await TransactionSync.pull(
                userId: userId, isPartial: false, writer: writer, backend: backend,
                now: now, defaults: defaults
            )
        case .goals:
            try await GoalSync.pull(
                userId: userId, writer: writer, backend: backend, now: now, defaults: defaults
            )
        case .budgets:
            try await BudgetSync.pull(
                userId: userId, writer: writer, backend: backend, now: now, defaults: defaults
            )
        case .categories:
            try await CategorySync.pull(
                userId: userId, writer: writer, backend: backend, now: now, defaults: defaults
            )
        case .payees:
            try await PayeeSync.pull(
                userId: userId, writer: writer, backend: backend, now: now, defaults: defaults
            )
        case .quickTransactions:
            try await QuickTransactionSync.pull(
                userId: userId, writer: writer, backend: backend, now: now, defaults: defaults
            )
        case .transactionGroups:
            try await GroupSync.pull(
                userId: userId, writer: writer, backend: backend, now: now, defaults: defaults
            )
        }
    }
}
