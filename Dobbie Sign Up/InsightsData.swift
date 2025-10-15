// InsightsData.swift
import Foundation
import SwiftUI
import Supabase
import Realtime

@MainActor
final class InsightsData: ObservableObject {
    static let shared = InsightsData()

    @Published var walkData: [WalkData] = []
    @Published var activityData: [ActivityData] = []
    @Published var pottyData: [PottyData] = []

    // Dog profile (unchanged)
    @Published var dogName: String = ""
    @Published var dogBreed: String = ""
    @Published var dogGender: String = ""
    @Published var dogDob: Date = Date()
    @Published var dogWeight: String = ""

    // Realtime v2
    private var channel: RealtimeChannelV2?
    private var subscriptions: [RealtimeSubscription] = []
    private var activeDogId: String?

    // MARK: - Refresh from Supabase
    func refreshFromSupabase() async {
        print("🔄 Refreshing dashboards from Supabase...")

        guard let dogId = try? await SupabaseManager.shared.getDogId() else {
            print("❌ No dogId found in InsightsData.refreshFromSupabase()")
            return
        }

        do {
            print("🔎 Fetching last 7 days of logs for dogId: \(dogId)")
            let logs = try await SupabaseManager.shared.fetchLast7DaysActivityLogs(dogId: dogId)
            print("✅ Received \(logs.count) logs from Supabase.")

            walkData     = logs.toWalkData()
            activityData = logs.toActivityData()
            pottyData    = logs.toPottyData()

            print("✅ Synced dashboards → walks=\(walkData.count), activity=\(activityData.count), potty=\(pottyData.count)")

            // 🔔 Notify other views (e.g., DoggieDashboardsView) to re-fetch their RPC data
            NotificationCenter.default.post(name: .activityLogsDidChange, object: nil)

        } catch {
            print("❌ Failed to fetch logs:", error.localizedDescription)
        }
    }


    // MARK: - Public: attach / detach realtime

    /// Call from a View/manager to start live updates.
    /// Safe to call repeatedly; it will recreate the channel when dog changes.
    func attachRealtime() async {
        guard let dogId = try? await SupabaseManager.shared.getDogId() else {
            print("❌ attachRealtime: no dogId")
            return
        }
        if dogId == activeDogId, channel != nil { return } // already attached

        await detachRealtime()

        let client = SupabaseManager.shared.client
        let ch = client.realtimeV2.channel("realtime:public:activity_logs")
        self.channel = ch
        self.activeDogId = dogId
        subscriptions.removeAll()

        // ---- REGISTER HANDLERS FIRST (v2 uses onPostgresChange) ----
        let f = "dog_id=eq.\(dogId)"

        let sIns = ch.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "activity_logs",
            filter: f
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshFromSupabase() }
        }

        let sUpd = ch.onPostgresChange(
            UpdateAction.self,
            schema: "public",
            table: "activity_logs",
            filter: f
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshFromSupabase() }
        }

        let sDel = ch.onPostgresChange(
            DeleteAction.self,
            schema: "public",
            table: "activity_logs",
            filter: f
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshFromSupabase() }
        }

        subscriptions = [sIns, sUpd, sDel] // keep them alive

        // ---- THEN SUBSCRIBE ----
        do {
            try await ch.subscribeWithError()
            print("📡 Subscribed to realtime (ins/upd/del) for dog \(dogId)")
        } catch {
            print("❌ subscribeWithError failed:", error.localizedDescription)
        }
    }

    /// Stop listening (call on view disappear or dog switch)
    func detachRealtime() async {
        if let ch = channel {
            await ch.unsubscribe()
        }
        channel = nil
        subscriptions.removeAll()
        activeDogId = nil
        print("🛑 Realtime detached")
    }
}
extension Notification.Name {
    static let activityLogsDidChange = Notification.Name("activityLogsDidChange")
}
