import SwiftUI

/// Placeholder auth gate shown when signed out.
///
/// The real Supabase email/password sign-in, session restore, and the 7-second
/// initialization timeout land in Phase 14 (DATA_ARCHITECTURE.md §3.5). The
/// mock sign-in simply flips the session so the shell can be exercised.
struct AuthGateView: View {
    @Environment(SessionStore.self) private var sessionStore

    @State private var email = ""
    @State private var password = ""

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
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
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                Button("Sign In") {
                    sessionStore.signInPlaceholder(
                        email: email.trimmingCharacters(in: .whitespaces)
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .keyboardShortcut(.defaultAction)
            }
            .frame(width: 260)

            Text("Placeholder sign-in — real authentication arrives with cloud sync.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
