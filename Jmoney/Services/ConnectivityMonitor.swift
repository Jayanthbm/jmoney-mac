import Foundation
import Network
import Observation

/// "Are we online?", the question `NetInfo.fetch()` answers in the React Native
/// app: `!!state.isConnected && !!state.isInternetReachable`.
///
/// A protocol rather than a concrete type because every sync entry point checks
/// it first, and tests need to drive both branches without touching the network.
protocol ConnectivityProviding: Sendable {
    func isOnline() async -> Bool
}

/// Always reports online. Used by the tests, and as the default for callers that
/// have no monitor (e.g. a unit test of a service that does not check).
struct AlwaysOnlineConnectivity: ConnectivityProviding {
    func isOnline() async -> Bool { true }
}

/// `NWPathMonitor`, replacing `@react-native-community/netinfo`.
///
/// `NWPathMonitor` reports "the route to the internet is usable" as
/// `.satisfied`, which is the macOS equivalent of `isConnected &&
/// isInternetReachable` combined. Unlike `NetInfo.fetch()`, the first read can
/// land before the monitor has produced a path; that is reported as **offline**
/// rather than optimistically online, so a sync can never start against an
/// unknown network state. Callers surface it as "offline" and the user retries.
@Observable
final class ConnectivityMonitor: ConnectivityProviding, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var latestPath: NWPath?

    /// Mirrors the latest `NWPath` for the UI (the status bar and the dashboard's
    /// sync modal both need to say "you are offline" without asking again).
    private(set) var isConnected = false

    init(startImmediately: Bool = true) {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.withLock { self.latestPath = path }
            let satisfied = path.status == .satisfied
            Task { @MainActor in self.isConnected = satisfied }
        }
        if startImmediately {
            monitor.start(queue: DispatchQueue(label: "com.jayanth.jmoney.connectivity"))
        }
    }

    deinit {
        monitor.cancel()
    }

    func isOnline() async -> Bool {
        // `latestPath?.status == .satisfied` is a plain Bool (a nil path compares
        // false), so no nil-coalescing is needed.
        lock.withLock { latestPath?.status == .satisfied }
    }
}
