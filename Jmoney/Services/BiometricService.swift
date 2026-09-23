import Foundation
import LocalAuthentication

/// Thin wrapper over `LAContext`, replacing `expo-local-authentication`.
///
/// The request/response rules live in `BiometricGate`, which is pure and tested;
/// this type only performs the framework calls and maps them onto that vocabulary.
///
/// Every `evaluatePolicy` call here is **main-actor isolated**. On macOS the auth
/// sheet is presented by the app's own process and must run with a run loop under
/// it — calling from a bare background task can hang or fail without presenting.
/// (The wrapper is intentionally *not* itself `@MainActor`, so `canEvaluatePolicy`
/// probes stay callable from anywhere, mirroring the source's capability calls.)
enum BiometricService {
    /// `hasHardwareAsync()` + `isEnrolledAsync()`.
    ///
    /// macOS reports both through a single `canEvaluatePolicy` call, so
    /// `biometryType` — which is populated by that call — is used to tell the two
    /// failures apart and reproduce the source's two-part check.
    static func availability() -> BiometricGate.Availability {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        if canEvaluate { return .available }
        // No Touch ID hardware at all ⇒ `biometryType` is `.none`; otherwise the
        // hardware exists and no fingerprint is enrolled.
        return context.biometryType == .none ? .noHardware : .notEnrolled
    }

    /// `authenticateAsync({ promptMessage })`.
    ///
    /// Biometrics only, as in the source — `.deviceOwnerAuthentication` would also
    /// accept the account password, which the source never does.
    @MainActor
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        guard
            context.canEvaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                error: nil
            )
        else { return false }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            // A cancel and a failure are the same to the source: `result.success`
            // is false and nothing changes.
            return false
        }
    }

    /// The prompt copy the source uses.
    static let enableReason = "Verify biometrics to enable app lock"

    /// `BiometricLock`'s `authenticateAsync({ promptMessage: 'Unlock Jmoney',
    /// disableDeviceFallback: false })`.
    ///
    /// The lock deliberately allows the OS account-password fallback — the source
    /// passes `disableDeviceFallback: false` — which on macOS is
    /// `.deviceOwnerAuthentication` (Touch ID first, then the account password).
    ///
    /// Main-actor isolation is load-bearing here: the sheet this call presents is
    /// the app's own window-context dialog, and `RootView` suppresses its
    /// re-lock-on-activation while this is in flight (see `AppState.isAuthPromptActive`).
    @MainActor
    static func unlock() async -> Bool {
        let context = LAContext()
        guard
            context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        else { return false }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Jmoney"
            )
        } catch {
            return false
        }
    }
}
