import LocalAuthentication
import Foundation

// Standalone probe for the app-lock's authentication stack.
// Runs the same two policies the app uses and logs the outcome with the
// underlying LAError code, so a failure can be attributed to the API layer
// rather than the app.
//
// Run from the repo root: `swift Scripts/la_probe.swift`

func name(_ error: NSError?) -> String {
    guard let error else { return "none" }
    return "LAError code \(error.code) — \(error.localizedDescription)"
}

@MainActor
func run(_ policy: LAPolicy, label: String) async {
    let context = LAContext()
    var error: NSError?
    let canEvaluate = context.canEvaluatePolicy(policy, error: &error)

    print("== \(label) ==")
    print("canEvaluatePolicy: \(canEvaluate) (\(name(error)))")

    guard canEvaluate else { return }

    do {
        let success = try await context.evaluatePolicy(
            policy,
            localizedReason: "Probe: unlock test for Jmoney diagnostics"
        )
        print("evaluatePolicy → success=\(success)")
    } catch {
        print("evaluatePolicy → failed: \(name(error as NSError))")
    }
}

let semaphore = DispatchSemaphore(value: 0)

Task { @MainActor in
    await run(.deviceOwnerAuthenticationWithBiometrics, label: "Biometrics only (enable flow)")
    print()
    await run(.deviceOwnerAuthentication, label: "With password fallback (lock screen)")
    exit(0)
}

dispatchMain()
