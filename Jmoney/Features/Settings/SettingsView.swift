import SwiftUI

/// The settings surface, shared by the sidebar's Settings pane and the ⌘, window.
///
/// Mirrors the React Native settings screen's four sections (Appearance,
/// Preferences, Manage Data, Account). The mobile→Mac mapping:
///
/// * the two-button Light/Dark selector becomes a three-way appearance picker
///   (the source's "key absent" state is System — see `AppearancePreference`);
/// * the reminder bottom sheet becomes a sheet with the same five rows;
/// * Manage Data entries **select the matching sidebar section** rather than
///   pushing a duplicate screen, which is what the RN `router.push('/goals')`
///   amounts to on a Mac;
/// * the logout / reset bottom sheets become native confirmation dialogs;
/// * the haptics row is present but inert, because Macs have no haptics hardware
///   (the matrix records this as MACOS EQUIVALENT → omit).
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database
    @Environment(AppearanceStore.self) private var appearance

    @State private var viewModel = SettingsViewModel()
    @State private var showReminderChooser = false
    @State private var confirmSignOut = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            appearanceSection
            preferencesSection
            manageDataSection
            accountSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.regularMaterial)
        .navigationTitle("Settings")
        .task { viewModel.load(userId: sessionStore.userId) }
        .onChange(of: viewModel.statusMessage) { _, message in
            // The status bar is the shell's toast surface (MACOS_ARCHITECTURE.md §4).
            if let message { appState.statusMessage = message }
        }
        .sheet(isPresented: $showReminderChooser) {
            ReminderChooserSheet(current: viewModel.reminder) { choice in
                Task { await viewModel.selectReminder(choice) }
            }
        }
        .alert("Sign Out", isPresented: $confirmSignOut) {
            Button("Yes, Sign Out", role: .destructive) { sessionStore.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to securely log out? Local data remains safe.")
        }
        .alert("Reset Data", isPresented: $confirmReset) {
            Button("Yes, Reset Everything", role: .destructive) { resetData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(resetConfirmationMessage)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: appearanceBinding) {
                ForEach(AppearancePreference.allCases) { preference in
                    Label(preference.title, systemImage: preference.systemImage)
                        .tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Appearance")
        }
    }

    /// The RN app's `setAppTheme` writes the choice immediately; so does this.
    private var appearanceBinding: Binding<AppearancePreference> {
        Binding(
            get: { appearance.preference },
            set: { appearance.select($0) }
        )
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        Section("Preferences") {
            SettingsRow(
                systemImage: "bell.badge",
                title: "Daily Reminders",
                detail: viewModel.reminderDetail
            ) {
                showReminderChooser = true
            }

            Toggle(
                isOn: Binding(
                    get: { viewModel.biometricsEnabled },
                    set: { value in
                        // Same activation guard as the lock screen: the enable
                        // prompt's sheet must not trigger the re-lock-on-active.
                        appState.isAuthPromptActive = true
                        Task {
                            defer { appState.isAuthPromptActive = false }
                            await viewModel.setBiometrics(value)
                        }
                    }
                )
            ) {
                SettingsRowLabel(
                    systemImage: "touchid",
                    title: "Use Touch ID",
                    detail: "Protect app with Touch ID"
                )
            }
            .toggleStyle(.switch)

            // The source persists a haptics preference that gates expo-haptics
            // calls. Macs have no haptic hardware, so there is nothing to gate —
            // the row is shown disabled and says why rather than vanishing.
            SettingsRow(
                systemImage: "hand.tap",
                title: "Haptic Feedback",
                detail: "Not available on Mac — no haptics hardware"
            ) { }
            .disabled(true)
        }
    }

    // MARK: - Manage Data

    private var manageDataSection: some View {
        Section("Manage Data") {
            SettingsRow(systemImage: "flag", title: "Goals", detail: "Manage Savings Goals") {
                open(.goals)
            }
            SettingsRow(
                systemImage: "square.grid.2x2", title: "Categories", detail: "Manage Categories"
            ) {
                open(.categories)
            }
            SettingsRow(systemImage: "person", title: "Payees", detail: "Manage Payees") {
                open(.payees)
            }
            SettingsRow(
                systemImage: "folder", title: "Transaction Groups", detail: "Manage Groups"
            ) {
                open(.groups)
            }
            SettingsRow(systemImage: "bolt", title: "Quick Transactions", detail: "Manage Templates")
            {
                open(.quickTransactions)
            }

            SettingsRow(
                systemImage: "arrow.triangle.2.circlepath",
                title: "Cloud Sync",
                detail: viewModel.syncDetail,
                tone: .normal
            ) {
                viewModel.refreshLastSync(userId: sessionStore.userId)
                appState.requestSync()
            }

            SettingsRow(
                systemImage: "trash",
                title: "Reset Data",
                detail: "Wipe all local records",
                tone: .destructive
            ) {
                confirmReset = true
            }
            .disabled(viewModel.isResetting)
        }
    }

    /// `router.push('/goals')` and friends — on macOS the destinations are
    /// sidebar sections, so select one instead of stacking a second copy.
    private func open(_ section: AppSection) {
        appState.selectedSection = section
    }

    /// The source's reset copy, plus the quirk the confirmation must not hide:
    /// `resetAppData` leaves `quick_transactions` untouched.
    private var resetConfirmationMessage: String {
        """
        This will permanently delete all your Transactions, Budgets, Goals, \
        and Categories. This action cannot be undone. Account info remains safe.

        Saved Quick Transaction templates are kept, matching the source app.
        """
    }

    private func resetData() {
        Task {
            let reset = await viewModel.resetData(
                pool: database.pool,
                userId: sessionStore.userId
            )
            guard reset else { return }
            // The RN handler ends with `router.replace('/(tabs)/dashboard')`, and
            // the remount is what refreshes the other screens.
            appState.markDataChanged()
            appState.selectedSection = .dashboard
            appearance.reload()
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section("Account") {
            LabeledContent("User Email", value: sessionStore.userEmail ?? "Guest")
            SettingsRow(
                systemImage: "rectangle.portrait.and.arrow.right",
                title: "Sign Out",
                detail: nil,
                tone: .destructive
            ) {
                confirmSignOut = true
            }
        }
    }
}

// MARK: - Rows

/// A settings row: icon tile, title, optional detail, and a chevron.
///
/// Stands in for the RN app's `SettingRow` + `NativeListItem` pair.
struct SettingsRow: View {
    enum Tone: Equatable {
        case normal
        case destructive

        var color: Color { self == .destructive ? .red : .accentColor }
    }

    let systemImage: String
    let title: String
    var detail: String?
    var showsChevron = true
    var tone: Tone = .normal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SettingsRowLabel(systemImage: systemImage, title: title, detail: detail, tone: tone)
                Spacer(minLength: 8)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The icon + two-line text block shared by `SettingsRow` and the toggle rows.
struct SettingsRowLabel: View {
    let systemImage: String
    let title: String
    var detail: String?
    var tone: SettingsRow.Tone = .normal

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: 26, height: 26)
                .background(tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
