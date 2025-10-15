import SwiftUI
import UIKit
import UserNotifications

// MARK: - Push delegate (APNs + Local notifications)
final class AppPushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    // MARK: - Universal Links from system/WhatsApp
    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return false }
        NotificationCenter.default.post(name: .didReceiveUniversalLink, object: url)
        return true
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted { DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() } }
            else { print("ℹ️ Notifications permission not granted (yet).") }
        }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) { completionHandler([.banner, .list, .sound, .badge]) }
        else { completionHandler([.alert, .sound, .badge]) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task { await SupabaseManager.shared.saveDeviceToken(tokenString) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ APNs registration failed:", error.localizedDescription)
    }
}

// MARK: - Cross-version onChange wrapper
private struct SignedInChangeModifier: ViewModifier {
    @Binding var isSignedIn: Bool
    let handle: (Bool) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.onChange(of: isSignedIn) { _, newValue in handle(newValue) }
        } else {
            content.onChange(of: isSignedIn) { newValue in handle(newValue) }
        }
    }
}
private extension View {
    func onSignedInChange(_ isSignedIn: Binding<Bool>, perform: @escaping (Bool) -> Void) -> some View {
        modifier(SignedInChangeModifier(isSignedIn: isSignedIn, handle: perform))
    }
}

// MARK: - App
@main
struct Dobbie_Sign_UpApp: App {
    @UIApplicationDelegateAdaptor(AppPushDelegate.self) var appDelegate

    @State private var isSignedIn = false
    @State private var isSetupComplete = false
    @StateObject private var setupVM = SetupViewModel()
    @State private var deepLinkError: String?
    @State private var justJoinedFamilyId: String?
    
    @State private var activeDogId: String? = nil

    // ✅ Queues
    @State private var pendingInviteToken: String?                 // legacy link ?token=
    @State private var pendingShareCode: String?                   // /join/<CODE> or manual

    private let pendingInviteKey = "pending_family_invite_token"
    private let pendingShareCodeKey = "pending_family_share_code"

    var body: some Scene {
        WindowGroup {
            Group {
                if !isSignedIn {
                    SignUpView(isSignedIn: $isSignedIn)
                        .task {
                            // Load any stashed token/code for later
                            if pendingInviteToken == nil, let t = loadPendingInvite() { pendingInviteToken = t }
                            if pendingShareCode == nil, let c = loadPendingShareCode() { pendingShareCode = c }

                            let valid = await SupabaseManager.shared.hasValidSession()
                            if valid {
                                // Fetch once; set dog id and derive setup state
                                let dogId = try? await SupabaseManager.shared.getDogId()
                                await MainActor.run {
                                    activeDogId = dogId
                                    isSetupComplete = (dogId != nil)
                                }
                            } else {
                                await MainActor.run {
                                    activeDogId = nil
                                    isSetupComplete = false
                                }
                            }
                        }

                } else if !isSetupComplete {
                    SetupWizardView(vm: setupVM, isSignedIn: $isSignedIn, isSetupComplete: $isSetupComplete)
                        .task(id: isSetupComplete) {
                            if isSetupComplete {
                                await consumePendingJoinIfAny(context: "after-setup")
                            }
                        }

                } else {
                    MainTabView(isSignedIn: $isSignedIn)
                        .task {
                            await refreshSetupState()
                            await SupabaseManager.shared.flushStagedDeviceTokenIfPossible()
                            await consumePendingJoinIfAny(context: "main-tab")
                        }
                }
            }
            .onSignedInChange($isSignedIn) { newValue in
                if newValue {
                    Task {
                        _ = await waitForValidSession()
                        await refreshSetupState()
                        await SupabaseManager.shared.flushStagedDeviceTokenIfPossible()
                        await consumePendingJoinIfAny(context: "after-signin")
                    }
                } else {
                    // Clear gates on sign-out
                    activeDogId = nil
                    isSetupComplete = false
                }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                handleUniversalLink(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .didReceiveUniversalLink)) { note in
                if let url = note.object as? URL { handleUniversalLink(url) }
            }
            .onOpenURL { url in handleUniversalLink(url) }
        }
    }

    // MARK: state helpers
    private func refreshSetupState() async {
        // Keep activeDogId in sync and derive setup state from it
        let dogId = try? await SupabaseManager.shared.getDogId()
        await MainActor.run {
            activeDogId = dogId
            isSetupComplete = (dogId != nil)
        }
    }

    private func waitForValidSession(timeout: TimeInterval = 6.0) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if await SupabaseManager.shared.hasValidSession() { return true }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return await SupabaseManager.shared.hasValidSession()
    }

    // MARK: acceptors
    @MainActor
    private func acceptToken(_ token: String) async throws -> String {
        let familyId = try await SupabaseManager.shared.acceptFamilyInvite(token: token)
        justJoinedFamilyId = familyId
        clearPendingInvite()
        await refreshSetupState()
        return familyId
    }

    @MainActor
    private func acceptShareCode(_ code: String) async throws -> String {
        let familyId = try await SupabaseManager.shared.acceptFamilyShareCode(code)
        justJoinedFamilyId = familyId
        clearPendingShareCode()
        await refreshSetupState()
        return familyId
    }

    private func consumePendingJoinIfAny(context: String) async {
        // Prefer share code (new flow)
        if let code = (pendingShareCode ?? loadPendingShareCode()),
           !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                print("🔁 Consuming pending SHARE CODE (\(context))…")
                _ = try await acceptShareCode(code)
                isSetupComplete = true
                return
            } catch {
                deepLinkError = error.localizedDescription
                print("❌ accept share code failed:", error.localizedDescription)
            }
        }
        // Fallback: legacy token link
        if let token = (pendingInviteToken ?? loadPendingInvite()),
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                print("🔁 Consuming pending TOKEN (\(context))…")
                _ = try await acceptToken(token)
                isSetupComplete = true
            } catch {
                deepLinkError = error.localizedDescription
                print("❌ accept token failed:", error.localizedDescription)
            }
        }
    }

    // MARK: URL routing
    private func handleUniversalLink(_ url: URL) {
        print("🔗 UL received:", url.absoluteString)
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "dobbie.app" || host == "www.dobbie.app" else {
            print("❌ UL ignored (bad host/scheme)")
            return
        }

        // 1) ?token=abc (legacy)
        if let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "token" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            if isSignedIn { Task { try? await acceptToken(token) } }
            else { savePendingInvite(token); print("🧳 Stashed invite token.") }
            return
        }

        // 2) /join/<CODE> or /invite/<CODE>  → treat as share code
        if let code = parseShareCode(from: url) {
            if isSignedIn { Task { try? await acceptShareCode(code) } }
            else { savePendingShareCode(code); print("🧳 Stashed share code.") }
            return
        }

        print("❌ UL missing token/code")
    }

    // MARK: persistence
    private func savePendingInvite(_ token: String?) {
        pendingInviteToken = token
        let d = UserDefaults.standard
        if let token { d.set(token, forKey: pendingInviteKey) } else { d.removeObject(forKey: pendingInviteKey) }
    }
    private func loadPendingInvite() -> String? { UserDefaults.standard.string(forKey: pendingInviteKey) }
    private func clearPendingInvite() { savePendingInvite(nil) }

    private func savePendingShareCode(_ code: String?) {
        pendingShareCode = code
        let d = UserDefaults.standard
        if let code { d.set(code, forKey: pendingShareCodeKey) } else { d.removeObject(forKey: pendingShareCodeKey) }
    }
    private func loadPendingShareCode() -> String? { UserDefaults.standard.string(forKey: pendingShareCodeKey) }
    private func clearPendingShareCode() { savePendingShareCode(nil) }
}

// Parse /join/<CODE> or /invite/<CODE> as a share code (not token)
fileprivate func parseShareCode(from url: URL) -> String? {
    let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard parts.count >= 2 else { return nil }
    let head = parts[0].lowercased()
    if head == "join" || head == "invite" {
        // leave any dashes; SupabaseManager.normalizeShareCode will clean
        return parts[1]
    }
    return nil
}

extension Notification.Name {
    static let didReceiveUniversalLink = Notification.Name("didReceiveUniversalLink")
}
