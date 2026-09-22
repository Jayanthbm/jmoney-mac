import Foundation

/// The app-lock state and the decision table behind the biometrics toggle.
///
/// Ports `src/hooks/useBiometrics.ts`, including its gate **order**: hardware,
/// then enrollment, then a successful authentication — the preference is only
/// persisted once all three pass. The framework calls live in `BiometricService`;
/// everything here is pure so the rules are testable without Touch ID hardware.
enum BiometricPreference {
    /// The key the source uses. It stores the *string* `"true"`/`"false"`, not a
    /// boolean, so the stored value is reproduced literally.
    static let storageKey = "use_biometrics"

    /// `AsyncStorage.getItem('use_biometrics') === 'true'` — note the strict
    /// comparison, so anything else (including an absent key) reads as disabled.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: storageKey) == "true"
    }

    static func save(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled ? "true" : "false", forKey: storageKey)
    }
}

/// The biometric capability checks, mirroring `expo-local-authentication`'s
/// `hasHardwareAsync` / `isEnrolledAsync` pair.
enum BiometricGate {
    /// `hasHardwareAsync()` + `isEnrolledAsync()` collapsed into one value (macOS
    /// reports both through `LAContext`, so `BiometricService` splits them apart
    /// again using `biometryType`).
    enum Availability: Equatable {
        /// `hasHardware && isEnrolled`.
        case available
        /// `!hasHardware`.
        case noHardware
        /// `hasHardware && !isEnrolled`.
        case notEnrolled

        /// The source's single error message for both failing cases: it reports
        /// "does not support biometrics **or** no fingerprints/faces enrolled"
        /// from one toast, so the two are deliberately not told apart in the UI.
        static let unavailableMessage =
            "Biometrics Unavailable: Your device does not support biometrics or no fingerprints/faces enrolled."

        var failureMessage: String? {
            self == .available ? nil : Self.unavailableMessage
        }
    }

    /// What the toggle should do, and what should be persisted or reported.
    enum Outcome: Equatable {
        /// Authentication succeeded: persist `true`.
        case enable
        /// The user asked to turn the lock off: persist `false` (no capability
        /// check — the source skips straight to the write).
        case disable
        /// No hardware / not enrolled: change nothing, report `message`.
        case unavailable(Availability)
        /// The authentication was cancelled or failed: change nothing and stay
        /// silent, exactly as the source does (it only acts on `result.success`).
        case unchanged

        /// The value to persist, or `nil` to leave the preference alone.
        var persistedValue: Bool? {
            switch self {
            case .enable: return true
            case .disable: return false
            case .unavailable, .unchanged: return nil
            }
        }

        /// The message to surface, if any.
        var message: String? {
            switch self {
            case .unavailable(let availability): return availability.failureMessage
            case .enable, .disable, .unchanged: return nil
            }
        }
    }

    /// `handleBiometricToggle` as a pure function.
    ///
    /// - Parameters:
    ///   - requested: the new switch value.
    ///   - availability: the capability check, consulted only when enabling.
    ///   - authenticated: whether the prompt succeeded (`result.success`).
    static func outcome(
        requested: Bool,
        availability: Availability,
        authenticated: Bool = false
    ) -> Outcome {
        guard requested else { return .disable }
        guard availability == .available else { return .unavailable(availability) }
        return authenticated ? .enable : .unchanged
    }
}
