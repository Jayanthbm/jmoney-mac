import Foundation
import LocalAuthentication

/// Thin wrapper over `LAContext`, replacing `expo-local-authentication`.
///
/// The request/response rules live in `BiometricGate`, which is pure and tested;
/// this type only performs the framework calls and maps them onto that vocabulary.
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
}
