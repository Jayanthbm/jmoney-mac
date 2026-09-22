import SwiftUI

/// The auth gate shown when signed out.
///
/// Replaces the Phase 4 mock. Sign-in is Supabase's `signInWithPassword` via
/// `SessionStore`, which keeps the source's minimal client-side rule: both fields
/// must be non-empty before the button is enabled, and anything else is the
/// server's answer. A failed attempt is reported inline rather than as a toast,
/// because the form is where the user is looking.
struct AuthGateView: View {
    @Environment(SessionStore.self) private var sessionStore

    @State private var email = ""
    @State private var password = ""

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespaces)
    }

    private var canSubmit: Bool {
        !trimmedEmail.isEmpty && !password.isEmpty && !sessionStore.isSigningIn
    }

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "banknote.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Jmoney")
                    .font(.largeTitle.bold())
                Text("Track your finances offline-first, with cloud sync.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .disabled(sessionStore.isSigningIn)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .disabled(sessionStore.isSigningIn)
                    .onSubmit { submit() }

                Button("Sign In") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                    .keyboardShortcut(.defaultAction)

                if sessionStore.isSigningIn {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Signing in")
                }
            }
            .frame(width: 280)

            statusText
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var statusText: some View {
        if let message = sessionStore.errorMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        } else if let configuration = sessionStore.configurationMessage {
            // An unconfigured build says so before the user tries, instead of
            // failing every attempt with a network error.
            Text(configuration)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        let email = trimmedEmail
        let password = password
        Task { await sessionStore.signIn(email: email, password: password) }
    }
}
