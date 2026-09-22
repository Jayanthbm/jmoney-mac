import Foundation
import UserNotifications

/// Schedules the daily expense reminder.
///
/// Ports `src/services/notificationService.ts`. The source's order is preserved:
/// request permission → cancel anything already scheduled → clear or schedule.
///
/// Two details carried over deliberately:
/// * the notification copy is the source's (`"Reminder 💰"` / the body below);
/// * a refused permission is reported rather than swallowed. The source only logs
///   it, which leaves the settings row claiming a reminder that will never
///   arrive, so the outcome is surfaced here as `.permissionDenied`.
///
/// Storing the preference is the caller's job, as it is in the source (the
/// `handleNotificationChange` hook writes `notification_pref` itself and then
/// calls `scheduleReminder`). `SettingsViewModel.selectReminder` does the same.
enum NotificationService {
    static let reminderTitle = "Reminder 💰"
    static let reminderBody = "Don't forget to add your expenses for today!"
    /// A fixed identifier: only one reminder is ever scheduled, and the source
    /// clears every pending request before adding the new one.
    static let requestIdentifier = "jmoney.daily.reminder"

    enum Outcome: Equatable {
        /// The daily reminder was scheduled.
        case scheduled
        /// The choice was `None`; the preference key was removed and any pending
        /// reminder cancelled.
        case cleared
        /// Permission was refused, so nothing was scheduled or cancelled. The
        /// preference was still recorded.
        case permissionDenied
    }

    /// `scheduleReminder(timeOfDay)`.
    @discardableResult
    static func schedule(
        _ preference: ReminderPreference,
        center: UNUserNotificationCenter = .current()
    ) async -> Outcome {
        // 1. Permission (the source re-requests on every change).
        var authorized = await isAuthorized(center)
        if !authorized {
            authorized =
                (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }

        // 2. The source returns here when permission was refused, leaving any
        //    pending request in place.
        guard authorized else { return .permissionDenied }

        // 3. Cancel whatever was scheduled before (the source cancels all).
        center.removeAllPendingNotificationRequests()

        guard let time = preference.scheduleTime else { return .cleared }

        let content = UNMutableNotificationContent()
        content.title = reminderTitle
        content.body = reminderBody
        content.sound = .default

        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: requestIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            return .scheduled
        } catch {
            return .permissionDenied
        }
    }

    /// Cancels the reminder without touching the stored preference. Not part of
    /// the source (nothing there cancels on sign-out); exported for completeness.
    static func cancelPending(center: UNUserNotificationCenter = .current()) {
        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
    }

    private static func isAuthorized(_ center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }
}
