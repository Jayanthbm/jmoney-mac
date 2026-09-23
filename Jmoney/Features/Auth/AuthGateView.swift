import AppKit
import SwiftUI

/// The modern AuthGateView shown when signed out.
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
        ZStack {
            // Modern gradient background
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.12),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                // App Icon from bundle NSApplication icon
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)

                VStack(spacing: 8) {
                    Text("Jmoney")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("Offline-first finance tracking with cloud sync")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("name@example.com", text: $email)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                            .textContentType(.username)
                            .disabled(sessionStore.isSigningIn)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("••••••••", text: $password)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                            .textContentType(.password)
                            .disabled(sessionStore.isSigningIn)
                            .onSubmit { submit() }
                    }

                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if sessionStore.isSigningIn {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(!canSubmit)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 12)
                .frame(width: 340)

                statusText
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var statusText: some View {
        if let message = sessionStore.errorMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        } else if let configuration = sessionStore.configurationMessage {
            Text(configuration)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        let email = trimmedEmail
        let password = password
        Task { await sessionStore.signIn(email: email, password: password) }
    }
}

