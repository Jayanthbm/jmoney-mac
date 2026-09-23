import SwiftUI

/// The biometric app-lock overlay — the macOS port of `src/components/BiometricLock.tsx`.
///
/// The source covers the window while `isLocked` is true, auto-prompts on mount,
/// and offers an explicit retry button after a failure. This port keeps all three
/// behaviours; a macOS window cannot be "covered" by another view, so the lock
/// fills the window instead (the source's full-screen `container` does the same).
///
/// The prompt uses the source's copy ("Unlock Jmoney"). Unlike the enable flow,
/// this path is *not* biometrics-only in spirit — the source passes
/// `disableDeviceFallback: false`, so the OS password fallback is available, and
/// `.deviceOwnerAuthentication` is the macOS equivalent of that request.
struct AppLockView: View {
    /// Called after a successful unlock.
    let onUnlock: () -> Void
    @Environment(AppState.self) private var appState

    @State private var isAuthenticating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "touchid")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Jmoney Locked")
                .font(.title.bold())

            Text("Please authenticate to access your financial data")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            Button {
                authenticate()
            } label: {
                Label("Unlock App", systemImage: "lock.open")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
            .padding(.top, 8)

            if isAuthenticating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Authenticating")
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { authenticate() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Jmoney is locked")
    }

    /// `authenticateAsync({ promptMessage: 'Unlock Jmoney', disableDeviceFallback: false })`.
    ///
    /// A cancel and a failure are the same to the source — `result.success` is
    /// false and the error box appears — so both are reported identically here.
    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        appState.isAuthPromptActive = true
        Task {
            defer { appState.isAuthPromptActive = false }
            let success = await BiometricService.unlock()
            isAuthenticating = false
            if success {
                onUnlock()
            } else {
                errorMessage = "Authentication failed"
            }
        }
    }
}
