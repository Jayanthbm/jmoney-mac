import Foundation
import CoreLocation

/// CoreLocation wrapper — the `expo-location` replacement, keeping the
/// `BiometricService` split: pure rules live in `LocationGate`, this type only
/// performs the framework calls.
///
/// Everything runs on the main actor: `CLLocationManager` expects to be created
/// on a thread with an active run loop, and its delegate callbacks arrive there.
@MainActor
enum LocationService {
    /// `Location.requestForegroundPermissionsAsync()`. An already-granted status
    /// short-circuits; otherwise the system prompt is shown. A denial (or a
    /// system that never answers) is `false`, like the source's non-granted branch.
    static func requestPermission() async -> Bool {
        let manager = CLLocationManager()
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            break // fall through to the prompt
        @unknown default:
            return false
        }
        return await withCheckedContinuation { continuation in
            let delegate = PermissionDelegate { granted in
                continuation.resume(returning: granted)
            }
            manager.delegate = delegate
            manager.requestWhenInUseAuthorization()
            // Safety net: if the system never calls back (Location Services
            // disabled before the prompt), don't hang the editor. Treated as a
            // denial, like the source's non-granted branch.
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                delegate.finish(with: false)
            }
        }
    }

    /// `Location.getLastKnownPositionAsync({})` — the cache read, no waiting.
    static func lastKnown() -> LocationGate.Fix? {
        guard let location = CLLocationManager().location else { return nil }
        return LocationGate.Fix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            source: .lastKnown
        )
    }

    /// One `getCurrentPositionAsync({ accuracy })` rung; the ladder's per-rung
    /// timeout is applied by `captureBestFix`.
    static func currentLocation(accuracy: CLLocationAccuracy) async -> LocationGate.Fix? {
        let manager = CLLocationManager()
        manager.desiredAccuracy = accuracy
        return await withCheckedContinuation { continuation in
            let delegate = FixDelegate { fix in
                continuation.resume(returning: fix)
            }
            manager.delegate = delegate
            manager.requestLocation()
        }
    }

    /// The full `fetchLocation` strategy: permission, last-known fallback, then
    /// the progressive-accuracy ladder with per-rung timeouts. `.failed` is
    /// returned exactly where the source clears the location — every rung failed
    /// with no last-known fix. Permission-denied is its own case so the UI can
    /// report the source's exact toast copy.
    enum CaptureOutcome {
        case denied
        case failed
        case fix(LocationGate.Fix)
    }

    static func captureOutcome() async -> CaptureOutcome {
        guard await requestPermission() else { return .denied }

        // Phase 1: the immediate last-known fallback.
        let lastKnownFix = lastKnown()

        // Phase 2: the ladder — each rung raced against its timeout.
        for rung in LocationGate.ladder {
            if let fix = await withTimeout(seconds: rung.timeout, operation: {
                await LocationService.currentLocation(accuracy: rung.accuracy)
            }) {
                return .fix(fix)
            }
        }

        // Total failure with a last-known fallback: the source keeps it
        // (its `!lastKnownUsed` guard). Total failure without one: cleared.
        if let lastKnownFix {
            return .fix(lastKnownFix)
        }
        return .failed
    }

    /// Convenience for callers that only care whether a fix landed.
    static func captureBestFix() async -> LocationGate.Fix? {
        if case .fix(let fix) = await captureOutcome() { return fix }
        return nil
    }

    private static func withTimeout(
        seconds: TimeInterval,
        operation: @escaping () async -> LocationGate.Fix?
    ) async -> LocationGate.Fix? {
        await withTaskGroup(of: LocationGate.Fix?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Delegates

    /// CLLocationManager reports the authorization answer through a delegate;
    /// these small holders translate it into the continuation result.
    private final class PermissionDelegate: NSObject, CLLocationManagerDelegate {
        private let onResult: (Bool) -> Void
        private var finished = false

        init(onResult: @escaping (Bool) -> Void) {
            self.onResult = onResult
        }

        func finish(with granted: Bool) {
            guard !finished else { return }
            finished = true
            onResult(granted)
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                finish(with: true)
            case .denied, .restricted:
                finish(with: false)
            case .notDetermined:
                break // waiting for the user's answer
            @unknown default:
                finish(with: false)
            }
        }
    }

    private final class FixDelegate: NSObject, CLLocationManagerDelegate {
        private let onFix: (LocationGate.Fix?) -> Void
        private var finished = false

        init(onFix: @escaping (LocationGate.Fix?) -> Void) {
            self.onFix = onFix
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard !finished else { return }
            guard let location = locations.last else {
                finished = true
                onFix(nil)
                return
            }
            finished = true
            onFix(LocationGate.Fix(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                source: .current
            ))
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            guard !finished else { return }
            finished = true
            onFix(nil)
        }
    }
}
