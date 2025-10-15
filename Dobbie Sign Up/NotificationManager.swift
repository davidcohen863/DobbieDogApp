import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    enum AuthState { case notDetermined, denied, authorized }

    func authState() async -> AuthState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied:        return .denied
        default:             return .authorized
        }
    }

    @MainActor
    func requestAuthIfNeeded(onDenied: (() -> Void)? = nil) async -> Bool {
        let state = await authState()
        switch state {
        case .authorized:
            return true
        case .notDetermined:
            do {
                let ok = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                return ok
            } catch {
                return false
            }
        case .denied:
            onDenied?()
            return false
        }
    }

    // Use a stable namespace so we can cancel by reminderId
    private func id(for reminderId: UUID, at date: Date) -> String {
        let t = Int(date.timeIntervalSince1970)
        return "reminder.\(reminderId.uuidString).\(t)"
    }

    func cancelAll(for reminderId: UUID) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()        // async
        let ids = pending.map(\.identifier).filter { $0.contains(reminderId.uuidString) }
        center.removePendingNotificationRequests(withIdentifiers: ids)  // <- no await
    }

    /// Schedules up to `cap` next fires (iOS cap is 64 per app).
    func schedule(
        reminderId: UUID,
        title: String,
        body: String?,
        times: [Date],
        cap: Int = 64
    ) async {
        guard !times.isEmpty else { return }
        let center = UNUserNotificationCenter.current()

        // Respect global 64 cap: schedule earliest first, up to `cap`
        let sorted = times.sorted().prefix(cap)

        for date in sorted {
            let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: date)
            let content = UNMutableNotificationContent()
            content.title = title
            if let body, !body.isEmpty { content.body = body }
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: id(for: reminderId, at: date),
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                print("❌ schedule notif failed:", error.localizedDescription)
            }
        }
    }
}

#if DEBUG
// ===============================================================
// MARK: - Debug helpers (compiled only in DEBUG builds)
// ===============================================================
extension NotificationManager {

    /// Fire a local notification in `seconds` (quick sanity check)
    @MainActor
    func scheduleDebugIn(
        seconds: TimeInterval = 5,
        title: String = "Dobbie Test",
        body: String = "If you see this, local notifications work!"
    ) async {
        let ok = await requestAuthIfNeeded()
        guard ok else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let req = UNNotificationRequest(
            identifier: "debug.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(req)
            print("✅ Scheduled debug notification in \(Int(seconds))s")
        } catch {
            print("❌ Failed to schedule debug notification:", error.localizedDescription)
        }
    }

    /// Print all pending local notification request identifiers
    func printPending() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        print("🔎 Pending (\(pending.count)):")
        for p in pending { print("• \(p.identifier)") }
    }

    /// Remove all pending local notifications
    func removeAllPending() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("🧹 Cleared all pending local notifications")
    }
}
#endif
