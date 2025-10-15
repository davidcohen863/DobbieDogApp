import SwiftUI

final class InvitationFlow {
    static let shared = InvitationFlow()
    private init() {}

    @AppStorage("pending_invite_token") private var pendingToken: String = ""

    @MainActor
    func handle(token: String) async {
        let hasSession = (try? await SupabaseManager.shared.client.auth.session) != nil
        if !hasSession {
            pendingToken = token            // wait until user logs in
            return
        }
        await redeem(token: token)
    }

    @MainActor
    func redeemIfPendingAfterLogin() async {
        guard !pendingToken.isEmpty else { return }
        let t = pendingToken
        pendingToken = ""
        await redeem(token: t)
    }

    @MainActor
    private func redeem(token: String) async {
        do {
            _ = try await SupabaseManager.shared.acceptFamilyInvite(token: token) // <- rename
            haptic(.success)
        } catch {
            haptic(.error)
            print("Invite redeem failed: \(error.localizedDescription)")
        }
    }

}
