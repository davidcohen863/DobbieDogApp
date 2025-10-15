//
//  SupabaseManager.swift
//  Dobbie Sign Up
//
//  Created by David Cohen on 24/09/2025.
//

import Foundation
import Supabase
import Realtime
import Security

// MARK: - ISO8601 helpers
private let isoZ: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f
}()

private func isoString(_ date: Date) -> String { isoZ.string(from: date) }

// ===============================================================
// MARK: - Realtime
// ===============================================================

extension SupabaseManager {
    private struct RealtimeStore {
        static var activityChannel: RealtimeChannelV2?
        static var activeDogId: String?
        static var subscriptions: [RealtimeSubscription] = [] // keep callbacks alive
    }

    /// Listen to INSERT/UPDATE/DELETE on `activity_logs` for a dog.
    /// IMPORTANT: Handlers are attached BEFORE subscribe().
    @MainActor
    func startActivityLogsRealtime(
        dogId: String,
        onChange: @escaping () -> Void
    ) async {
        // Avoid duplicate subscribe for the same dog
        if RealtimeStore.activeDogId == dogId, RealtimeStore.activityChannel != nil {
            return
        }

        // Tear down any existing channel & callbacks to avoid duplicates
        if let ch = RealtimeStore.activityChannel {
            await ch.unsubscribe()
        }
        RealtimeStore.activityChannel = nil
        RealtimeStore.activeDogId = nil
        RealtimeStore.subscriptions.removeAll()

        // Create v2 channel
        let channel = client.realtimeV2.channel("realtime:public:activity_logs")

        // ---- REGISTER HANDLERS FIRST (using onPostgresChange) ----
        let s1 = channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "activity_logs",
            filter: "dog_id=eq.\(dogId)"
        ) { _ in onChange() }

        let s2 = channel.onPostgresChange(
            UpdateAction.self,
            schema: "public",
            table: "activity_logs",
            filter: "dog_id=eq.\(dogId)"
        ) { _ in onChange() }

        let s3 = channel.onPostgresChange(
            DeleteAction.self,
            schema: "public",
            table: "activity_logs",
            filter: "dog_id=eq.\(dogId)"
        ) { _ in onChange() }

        // Keep subscriptions alive
        RealtimeStore.subscriptions = [s1, s2, s3]

        // ---- THEN SUBSCRIBE ----
        try? await channel.subscribeWithError()
        RealtimeStore.activityChannel = channel
        RealtimeStore.activeDogId = dogId

        print("✅ Realtime v2 subscribed (ins/upd/del) for dog \(dogId)")
    }

    @MainActor
    func stopActivityLogsRealtime() async {
        if let ch = RealtimeStore.activityChannel {
            await ch.unsubscribe()
        }
        RealtimeStore.activityChannel = nil
        RealtimeStore.activeDogId = nil
        RealtimeStore.subscriptions.removeAll()
        print("🛑 Realtime v2 unsubscribed")
    }
}

// ===============================================================
// MARK: - Alone plan (unchanged)
// ===============================================================

extension SupabaseManager {
    private struct AlonePlanUpdate: Encodable {
        let success: Bool
        let rating: Int?
        let notes: String?
        let completed_at: String
    }

    func completeLatestAlonePlan(success: Bool, rating: Int?, notes: String?) async throws {
        guard let dogId = try await getDogId() else { return }

        struct Row: Decodable { let id: String }
        let latest: [Row] = try await client
            .from("alone_time_plans")
            .select("id")
            .eq("dog_id", value: dogId)
            .order("generated_at", ascending: false)
            .limit(1)
            .execute()
            .value

        guard let id = latest.first?.id else { return }

        let iso = isoString(Date())
        let payload = AlonePlanUpdate(
            success: success,
            rating: rating,
            notes: notes,
            completed_at: iso
        )

        _ = try await client
            .from("alone_time_plans")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }
}

// ===============================================================
// MARK: - Activity CRUD + decoding
// ===============================================================

extension SupabaseManager {

    // Tolerant date decode for server responses
    private func decodeActivityLog(from data: Data) throws -> ActivityLog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)

            let f1 = isoZ
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            f2.timeZone = TimeZone(secondsFromGMT: 0)

            if let d = f1.date(from: s) ?? f2.date(from: s) {
                return d
            }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date format: \(s)")
        }
        return try decoder.decode(ActivityLog.self, from: data)
    }

    /// Inserts a new activity row and returns the created row (with `id`) so you can open the editor immediately.
    func createActivity(dogId: String, eventType: String, at date: Date) async throws -> ActivityLog {
        struct Insert: Codable {
            let dog_id: String
            let event_type: String
            let timestamp: Date
        }

        let payload = Insert(
            dog_id: dogId,
            event_type: eventType.lowercased(),
            timestamp: date // send native Date for timestamptz
        )

        let response = try await client
            .from("activity_logs")
            .insert(payload)
            .select()
            .single()
            .execute()

        let created = try decodeActivityLog(from: response.data)
        print("✅ Created activity \(created.event_type) with id \(created.id)")
        return created
    }
}

// ===============================================================
// MARK: - SupabaseManager singleton
// ===============================================================

final class SupabaseManager {
    static let shared = SupabaseManager()
    @Published var lastError: String?

    let baseURL = URL(string: "https://uxmhlsqnofedpqmbhzqg.supabase.co")!

    var functionsBaseURL: URL {
        let comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let host = comps.host?.replacingOccurrences(of: ".supabase.co", with: ".functions.supabase.co") ?? ""
        return URL(string: "https://\(host)")!
    }

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: baseURL,
            supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV4bWhsc3Fub2ZlZHBxbWJoenFnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg1NDk5NjYsImV4cCI6MjA3NDEyNTk2Nn0.-_YWzO4Cr19OlAu7P97m_r_ziUih_IgWTT5rGkCZJyM"
        )
        
    }

    // MARK: - Error Handling
    private func handleError(_ error: Error) {
        DispatchQueue.main.async {
            self.lastError = error.localizedDescription
        }
    }

    // MARK: - Auth Utils
    func getCurrentSession() async -> Session? {
        do { return try await client.auth.session }
        catch {
            print("⚠️ No active session:", error.localizedDescription)
            return nil
        }
    }

    func getCurrentUserId() async -> String? {
        if let session = try? await client.auth.session {
            return session.user.id.uuidString
        }
        return nil
    }

    func restoreSession() async -> Bool {
        do {
            let session = try await client.auth.session
            print("✅ Session restored for user: \(session.user.id)")
            return true
        } catch {
            print("⚠️ No active session:", error.localizedDescription)
            return false
        }
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
            clearDogCache()
            print("✅ User signed out and dog cache cleared")
        } catch {
            print("❌ Sign out failed:", error.localizedDescription)
        }
    }

    func ping() async {
        do {
            let session = try await client.auth.session
            print("✅ Supabase connected. Current user:", session.user.id)
        } catch {
            print("❌ Supabase error:", error.localizedDescription)
        }
    }

    // MARK: - ActivityLog Model
    struct ActivityLog: Codable {
        let id: UUID
        let dog_id: String
        let event_type: String
        let timestamp: Date
        var notes: String?
    }

    // MARK: Walk types (app-level)
    enum WalkSource: String, Codable { case manual, apple_health }

    struct WalkMetadata: Codable {
        var source: WalkSource
        var start_time: Date
        var end_time: Date
        var duration_s: Int
        var distance_m: Double?
        var calories_kcal: Double?
        var health_workout_id: String?
    }
}

// MARK: - Families (model + active family)
extension SupabaseManager {
    struct Family: Codable, Identifiable {
        let id: String
        let name: String
        let created_by: String
        let created_at: String
    }

    private var activeFamilyKey: String { "activeFamilyId" }

    @MainActor
    func setActiveFamilyId(_ id: String?) {
        let d = UserDefaults.standard
        if let id { d.set(id, forKey: activeFamilyKey) } else { d.removeObject(forKey: activeFamilyKey) }
        clearDogCache() // ensure getDogId() reselects under new family
    }

    func getActiveFamilyId() -> String? {
        UserDefaults.standard.string(forKey: activeFamilyKey)
    }
}
// MARK: - Families CRUD
extension SupabaseManager {
    @MainActor
    func createFamily(name: String) async throws -> Family {
        // Insert family
        let fam: Family = try await client
            .from("families")
            .insert(["name": name, "created_by": try await currentUserIdString()])
            .select()
            .single()
            .execute()
            .value

        // Ensure caller is a member (if you don't have an auto-membership trigger)
        try await client
            .from("family_members")
            .insert(["family_id": fam.id, "user_id": try await currentUserIdString()])
            .execute()

        setActiveFamilyId(fam.id)
        return fam
    }

    func myFamilies() async throws -> [Family] {
        try await client
            .from("families")
            .select()
            .order("created_at", ascending: true)
            .execute()
            .value
    }
}
// MARK: - Family Invites
extension SupabaseManager {
    private func randomTokenHex(_ bytes: Int = 24) -> String {
        var buffer = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &buffer)
        return buffer.map { String(format: "%02hhx", $0) }.joined()
    }

    struct FamilyInvite: Codable, Identifiable {
        let id: String
        let family_id: String
        let invited_email: String?
        let token: String
        let share_code: String?     // <-- add this
        let expires_at: String
        let accepted_by: String?
        let accepted_at: String?
        let created_by: String
        let created_at: String
        let status: String
    }


    /// Create a shareable invite URL for a family (valid 7 days)
    @MainActor
    func createFamilyInviteURL(familyId: String, email: String? = nil) async throws -> URL {
        struct InviteInsert: Encodable {
            let family_id: String
            let invited_email: String?   // optional -> becomes NULL when nil
            let token: String
            let expires_at: String       // ISO8601
            let created_by: String
        }

        let token = randomTokenHex(24)
        let expires = isoString(Date().addingTimeInterval(7 * 24 * 3600))

        let row = InviteInsert(
            family_id: familyId,
            invited_email: email,
            token: token,
            expires_at: expires,
            created_by: try await currentUserIdString()
        )

        try await client
            .from("family_invites")
            .insert(row)
            .execute()

        var comps = URLComponents(string: "https://dobbie.app/join")!
        comps.queryItems = [URLQueryItem(name: "token", value: token)]
        return comps.url!
    }


    /// Accept an invite; returns the joined family_id and sets it active
    @MainActor
    func acceptFamilyInvite(token: String) async throws -> String {
        struct Resp: Decodable { let accept_family_invite: String }

        let rows: [Resp] = try await client
            .rpc("accept_family_invite", params: ["p_token": token])
            .execute()
            .value

        guard let familyId = rows.first?.accept_family_invite else {
            throw NSError(domain: "Invite", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Invite not found or already accepted"])
        }

        setActiveFamilyId(familyId)
        clearDogCache()
        return familyId
    }


    /// Pending invites for a family (not accepted, not expired)
    func pendingFamilyInvites(familyId: String) async throws -> [FamilyInvite] {
        try await client
            .from("family_invites")
            .select()
            .eq("family_id", value: familyId)
            .eq("status", value: "pending")
            .gt("expires_at", value: Date())
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Revoke an invite (mark as revoked)
    @MainActor
    func revokeFamilyInvite(inviteId: String) async throws {
        try await client
            .from("family_invites")
            .update(["status": "revoked"])
            .eq("id", value: inviteId)
            .execute()
    }
}


// ===============================================================
// MARK: - Generic activity helpers
// ===============================================================

extension SupabaseManager {

    // MARK: - Log Activity (send native Date)
    func logActivity(
        dogId: String,
        eventType: String,
        at time: Date = Date()
    ) async {
        struct Insert: Codable {
            let dog_id: String
            let event_type: String
            let timestamp: Date
        }

        let insert = Insert(
            dog_id: dogId,
            event_type: eventType.lowercased(),
            timestamp: time
        )

        do {
            try await client.from("activity_logs").insert(insert).execute()
            print("✅ Logged \(eventType) at \(time)")
        } catch {
            print("❌ Failed to log activity:", error.localizedDescription)
        }
    }

    // MARK: - Update Activity Log (keep timestamp as Date for consistency)
    func updateLog(_ updated: ActivityLog) async {
        do {
            struct Update: Codable {
                let event_type: String
                let timestamp: Date
                let notes: String?
            }

            let payload = Update(
                event_type: updated.event_type.lowercased(),
                timestamp: updated.timestamp,
                notes: updated.notes
            )

            try await client
                .from("activity_logs")
                .update(payload)
                .eq("id", value: updated.id)
                .execute()

            print("✅ UPDATED row in Supabase for id: \(updated.id)")
        } catch {
            print("❌ Update failed:", error.localizedDescription)
        }
    }

    // MARK: - Delete Activity Log
    func deleteLog(_ log: ActivityLog) async {
        do {
            try await client
                .from("activity_logs")
                .delete()
                .eq("id", value: log.id)
                .execute()

            print("🗑️ DELETED row in Supabase for id: \(log.id)")
        } catch {
            print("❌ Delete failed in SupabaseManager:", error.localizedDescription)
        }
    }

    // MARK: - Fetch windows
    func fetchActivityLogs(dogId: String, from start: Date, to end: Date) async throws -> [ActivityLog] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)

            let f1 = isoZ
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            f2.timeZone = TimeZone(secondsFromGMT: 0)

            if let d = f1.date(from: s) ?? f2.date(from: s) {
                return d
            }
            print("⚠️ Unrecognized timestamp format:", s)
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date format: \(s)")
        }

        print("🔎 Fetching logs for dogId: \(dogId), from \(start) to \(end)")

        let response = try await client
            .from("activity_logs")
            .select("*")
            .eq("dog_id", value: dogId)
            .gte("timestamp", value: start)
            .lt("timestamp", value: end)
            .order("timestamp", ascending: false)
            .execute()

        print("📦 Raw Supabase response size: \(response.data.count) bytes")

        do {
            let logs = try decoder.decode([ActivityLog].self, from: response.data)
            print("✅ Decoded \(logs.count) logs from Supabase.")
            if logs.isEmpty {
                print("⚠️ No logs returned. Check timestamp range & Supabase data types.")
            }
            return logs
        } catch {
            print("❌ Decoding error:", error)
            print("🧩 Raw JSON from Supabase:")
            print(String(data: response.data, encoding: .utf8) ?? "nil")
            throw error
        }
    }

    // MARK: - Convenience fetches
    func fetchLast7DaysActivityLogs(dogId: String) async throws -> [ActivityLog] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -6, to: todayStart)!
        let end = cal.date(byAdding: .day, value: 1, to: todayStart)!
        return try await fetchActivityLogs(dogId: dogId, from: start, to: end)
    }

    func fetchActivityLogs(dogId: String, period: Period) async throws -> [ActivityLog] {
        let cal = Calendar.current
        let now = Date()
        let startDate: Date = {
            switch period {
            case .week:
                return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            case .month:
                return cal.date(from: cal.dateComponents([.year, .month], from: now))!
            }
        }()
        return try await fetchActivityLogs(dogId: dogId, from: startDate, to: now)
    }

    func fetchGroupedLogs(dogId: String, period: Period) async throws -> [String: [String: Int]] {
        let logs = try await fetchActivityLogs(dogId: String(dogId), period: period)
        return logs.groupedByDay()
    }
}

// ===============================================================
// MARK: - Dog ID cache
// ===============================================================

extension SupabaseManager {
    private var cachedDogId: String? {
        get { UserDefaults.standard.string(forKey: "cachedDogId") }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: "cachedDogId") }
            else { UserDefaults.standard.removeObject(forKey: "cachedDogId") }
        }
    }

    func cacheDogId(_ id: String) { cachedDogId = id }

    /// NEW: forceRefresh allows callers to bypass the cache after membership changes.
    func getDogId(forceRefresh: Bool = false) async throws -> String? {
        if !forceRefresh, let id = cachedDogId { return id }
        _ = try await client.auth.session

        if let fid = getActiveFamilyId() {
            struct Row: Decodable { let id: String }
            let rows: [Row] = try await client
                .from("dogs").select("id")
                .eq("family_id", value: fid)
                .order("created_at", ascending: true)
                .limit(1)
                .execute()
                .value
            if let id = rows.first?.id { cacheDogId(id); return id }
            return nil
        }

        // fallback: any accessible dog
        struct Row: Decodable { let id: String }
        let rows: [Row] = try await client
            .from("dogs").select("id")
            .order("created_at", ascending: true)
            .limit(1)
            .execute()
            .value
        if let id = rows.first?.id { cacheDogId(id); return id }
        return nil
    }



    func clearDogCache() {
        cachedDogId = nil
    }
}

// ===============================================================
// MARK: - Device tokens (with staging/flush)
// ===============================================================

extension SupabaseManager {
    // Staging in case user/dog isn’t ready yet at token time
    private var stagedAPNsKey: String { "staged_apns_token" }

    private func stageDeviceToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: stagedAPNsKey)
    }

    private func popStagedDeviceToken() -> String? {
        let v = UserDefaults.standard.string(forKey: stagedAPNsKey)
        if v != nil { UserDefaults.standard.removeObject(forKey: stagedAPNsKey) }
        return v
    }

    /// Call after login and once setup/dog exists.
    @MainActor
    func flushStagedDeviceTokenIfPossible() async {
        if let token = UserDefaults.standard.string(forKey: stagedAPNsKey) {
            await saveDeviceToken(token)
        }
    }

    func saveDeviceToken(_ token: String) async {
        do {
            guard let session = try? await client.auth.session else {
                stageDeviceToken(token); return
            }
            let userId = session.user.id.uuidString
            guard let dogId = try await getDogId() else {
                stageDeviceToken(token); return
            }

            struct Insert: Codable {
                let user_id: String
                let dog_id: String
                let token: String
                let platform: String
                let environment: String
            }

            #if DEBUG
            let env = "sandbox"
            #else
            let env = (Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt") ? "sandbox" : "production"
            #endif

            let row = Insert(
                user_id: userId,
                dog_id: dogId,
                token: token,
                platform: "ios",
                environment: env
            )

            try await client
                .from("device_tokens")
                .upsert(row, onConflict: "user_id,token")
                .execute()

            // success; clear staged if same
            if UserDefaults.standard.string(forKey: stagedAPNsKey) == token {
                UserDefaults.standard.removeObject(forKey: stagedAPNsKey)
            }
            print("✅ Saved APNs token (\(env))")
        } catch {
            stageDeviceToken(token)
            print("❌ saveDeviceToken failed:", error.localizedDescription)
        }
    }
}

// ===============================================================
// MARK: - Walk & Sleep metadata (DB-facing structs with ISO strings)
// ===============================================================

extension SupabaseManager {
    // DB payloads: ISO strings inside JSON so SQL filters like metadata->>'end_time' work reliably.
    struct WalkMetadataDB: Codable {
        var source: String               // "manual" | "apple_health"
        var start_time: String           // ISO8601Z
        var end_time: String             // ISO8601Z
        var duration_s: Int
        var distance_m: Double?
        var calories_kcal: Double?
        var health_workout_id: String?
    }

    struct SleepMetadataDB: Codable {
        var source: String               // "manual"
        var start_time: String           // ISO8601Z
        var end_time: String             // ISO8601Z
        var duration_s: Int
    }
}

// ===============================================================
// MARK: - Walk Insert/Update (metadata as JSON object)
// ===============================================================

extension SupabaseManager {
    private struct WalkInsert: Encodable {
        let dog_id: String
        let event_type: String           // "walk"
        let timestamp: Date              // use END time as primary timestamp
        let notes: String?
        let metadata: WalkMetadataDB
    }

    @MainActor
    func insertWalkLog(
        dogId: String,
        metadata: WalkMetadata,
        notes: String?
    ) async throws {
        let metaDB = WalkMetadataDB(
            source: metadata.source.rawValue,
            start_time: isoString(metadata.start_time),
            end_time: isoString(metadata.end_time),
            duration_s: metadata.duration_s,
            distance_m: metadata.distance_m,
            calories_kcal: metadata.calories_kcal,
            health_workout_id: metadata.health_workout_id
        )

        let payload = WalkInsert(
            dog_id: dogId,
            event_type: "walk",
            timestamp: metadata.end_time,  // keep as Date for timestamptz column
            notes: notes,
            metadata: metaDB
        )

        try await client
            .from("activity_logs")
            .insert(payload)
            .execute()
    }
}

extension SupabaseManager {
    private struct WalkUpdate: Encodable {
        let event_type: String = "walk"
        let timestamp: Date            // use end_time as primary timestamp
        let notes: String?
        let metadata: WalkMetadataDB
    }

    @MainActor
    func updateWalkLog(
        id: UUID,
        metadata: WalkMetadata,
        notes: String?
    ) async throws {
        let metaDB = WalkMetadataDB(
            source: metadata.source.rawValue,
            start_time: isoString(metadata.start_time),
            end_time: isoString(metadata.end_time),
            duration_s: metadata.duration_s,
            distance_m: metadata.distance_m,
            calories_kcal: metadata.calories_kcal,
            health_workout_id: metadata.health_workout_id
        )

        let payload = WalkUpdate(
            timestamp: metadata.end_time,
            notes: notes,
            metadata: metaDB
        )

        try await client
            .from("activity_logs")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }
}

// ===============================================================
// MARK: - Sleep Insert/Update (metadata as JSON object)
// ===============================================================

extension SupabaseManager {
    enum SleepSource: String, Codable { case manual /*, apple_health*/ }

    struct SleepMetadata: Codable {
        var source: SleepSource
        var start_time: Date
        var end_time: Date
        var duration_s: Int
    }
}

extension SupabaseManager {
    private struct SleepInsert: Encodable {
        let dog_id: String
        let event_type: String           // "sleep"
        let timestamp: Date              // use END time
        let notes: String?
        let metadata: SleepMetadataDB
    }

    @MainActor
    func insertSleepLog(
        dogId: String,
        metadata: SleepMetadata,
        notes: String?
    ) async throws {
        let metaDB = SleepMetadataDB(
            source: metadata.source.rawValue,
            start_time: isoString(metadata.start_time),
            end_time: isoString(metadata.end_time),
            duration_s: metadata.duration_s
        )

        let payload = SleepInsert(
            dog_id: dogId,
            event_type: "sleep",
            timestamp: metadata.end_time,
            notes: notes,
            metadata: metaDB
        )

        try await client
            .from("activity_logs")
            .insert(payload)
            .execute()
    }
}

extension SupabaseManager {
    private struct SleepUpdate: Encodable {
        let event_type: String = "sleep"
        let timestamp: Date            // use end_time
        let notes: String?
        let metadata: SleepMetadataDB
    }

    @MainActor
    func updateSleepLog(
        id: UUID,
        metadata: SleepMetadata,
        notes: String?
    ) async throws {
        let metaDB = SleepMetadataDB(
            source: metadata.source.rawValue,
            start_time: isoString(metadata.start_time),
            end_time: isoString(metadata.end_time),
            duration_s: metadata.duration_s
        )

        let payload = SleepUpdate(
            timestamp: metadata.end_time,
            notes: notes,
            metadata: metaDB
        )

        try await client
            .from("activity_logs")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }
}

// ===============================================================
// MARK: - DateFormatter utils (kept for other callers)
// ===============================================================

extension DateFormatter {
    static var appFormat: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = .current
        return f
    }
}

extension Date {
    func convertToUTC() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.string(from: self)
    }
}

// MARK: - Reminders
extension SupabaseManager {
    struct Reminder: Codable {
        let id: UUID
        let dog_id: String
        var title: String
        var notes: String?
        var schedule_type: String   // "once" | "daily" | "weekly" | "interval" | "monthly"
        var weekday_mask: Int?
        var interval_days: Int?
        var date_once: String?
        var times: [String]         // ["13:00","19:15"]
        var start_date: String      // "YYYY-MM-DD"
        var end_date: String?
        var tz: String
        var is_active: Bool
        var notifications_enabled: Bool?
        let created_at: Date?
        let updated_at: Date?
    }

    struct ReminderOccurrence: Codable, Identifiable {
        let id: UUID
        let reminder_id: UUID
        let dog_id: String
        let occurs_at: Date
        var status: String          // "pending" | "done" | "dismissed" | "canceled"
    }
}

// A joined row: occurrence + parent reminder's title
extension SupabaseManager {
    struct ReminderOccurrenceWithTitle: Codable, Identifiable {
        let id: UUID
        let reminder_id: UUID
        let dog_id: String
        let occurs_at: Date
        var status: String
        // Embedded relation "reminders" with only `title`
        struct ReminderRef: Codable { let title: String? }
        let reminders: ReminderRef?
    }
}

// Fetch occurrences with reminder title via relation
extension SupabaseManager {
    func fetchReminderOccurrencesWithTitle(
        dogId: String,
        from: Date,
        to: Date
    ) async throws -> [ReminderOccurrenceWithTitle] {
        try await client
            .from("reminder_occurrences")
            .select("id, reminder_id, dog_id, occurs_at, status, reminders(title)")
            .eq("dog_id", value: dogId)
            .gte("occurs_at", value: from)
            .lt("occurs_at", value: to)
            .order("occurs_at", ascending: true)
            .execute()
            .value
    }
}

// MARK: - Reminder API
extension SupabaseManager {
    struct NewReminder {
        var title: String
        var notes: String?
        var scheduleType: String         // once/daily/weekly/interval/monthly
        var weekdayMask: Int?            // weekly
        var intervalDays: Int?           // interval
        var dateOnce: Date?              // once
        var times: [String]              // "HH:mm" local device tz
        var startDate: Date
        var endDate: Date?
        var tz: String = TimeZone.current.identifier
        var notificationsEnabled: Bool = true
    }

    /// Insert reminder and pre-expand its occurrences for next `horizonDays` (server will later take over)
    @MainActor
    func createReminder(dogId: String, new r: NewReminder, horizonDays: Int = 90) async throws -> Reminder {
        struct InsertPayload: Encodable {
            let dog_id: String, title: String, notes: String?
            let schedule_type: String, weekday_mask: Int?, interval_days: Int?
            let date_once: String?, times: [String], start_date: String, end_date: String?, tz: String
            let notifications_enabled: Bool
        }

        let dfDate = DateFormatter()
        dfDate.calendar = Calendar(identifier: .gregorian)
        dfDate.timeZone = .current
        dfDate.dateFormat = "yyyy-MM-dd"

        let payload = InsertPayload(
            dog_id: dogId,
            title: r.title,
            notes: r.notes,
            schedule_type: r.scheduleType,
            weekday_mask: r.weekdayMask,
            interval_days: r.intervalDays,
            date_once: r.dateOnce.map { dfDate.string(from: $0) },
            times: r.times,
            start_date: dfDate.string(from: r.startDate),
            end_date: r.endDate.map { dfDate.string(from: $0) },
            tz: r.tz,
            notifications_enabled: r.notificationsEnabled
        )

        // create base reminder
        let created: Reminder = try await client
            .from("reminders")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value

        // pre-expand occurrences (client-side for now)
        let occ = try expandOccurrences(reminder: created, horizonDays: horizonDays)
        if !occ.isEmpty {
            try await client.from("reminder_occurrences").insert(occ).execute()
        }
        return created
    }

    /// Expand to concrete occurrences in UTC (timestamptz) for the next N days
    private func expandOccurrences(reminder r: Reminder, horizonDays: Int) throws -> [OccurrenceInsert] {
        // Date-only formatter for YYYY-MM-DD
        let dfDate = DateFormatter()
        dfDate.calendar = Calendar(identifier: .gregorian)
        dfDate.timeZone = .current
        dfDate.dateFormat = "yyyy-MM-dd"

        guard let start = dfDate.date(from: r.start_date) else { return [] }
        let endCap = minEndDate(
            start: start,
            explicitEnd: r.end_date.flatMap { dfDate.date(from: $0) },
            horizonDays: horizonDays
        )

        // Calendar locked to the reminder's timezone
        let tz = TimeZone(identifier: r.tz) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        var out: [OccurrenceInsert] = []
        var day = start

        func makeDate(_ day: Date, hm: String) -> Date? {
            let parts = hm.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            let ymd = cal.dateComponents([.year, .month, .day], from: day)
            let comps = DateComponents(
                timeZone: tz,
                year: ymd.year, month: ymd.month, day: ymd.day,
                hour: parts[0], minute: parts[1], second: 0
            )
            return cal.date(from: comps)
        }

        func includeWeekday(_ date: Date, mask: Int) -> Bool {
            // Mon=1<<0 ... Sun=1<<6
            let w = cal.component(.weekday, from: date) // Sun=1 ... Sat=7
            let index = (w == 1) ? 6 : (w - 2)          // Mon=0..Sun=6
            return (mask & (1 << index)) != 0
        }

        switch r.schedule_type {
        case "once":
            if let d = r.date_once, let base = dfDate.date(from: d) {
                for t in r.times { if let at = makeDate(base, hm: t) {
                    out.append(OccurrenceInsert(reminder_id: r.id, dog_id: r.dog_id, occurs_at: at))
                }}
            }

        case "daily":
            while day <= endCap {
                for t in r.times { if let at = makeDate(day, hm: t) {
                    out.append(OccurrenceInsert(reminder_id: r.id, dog_id: r.dog_id, occurs_at: at))
                }}
                day = cal.date(byAdding: .day, value: 1, to: day)!
            }

        case "weekly":
            let mask = r.weekday_mask ?? 0
            while day <= endCap {
                if includeWeekday(day, mask: mask) {
                    for t in r.times { if let at = makeDate(day, hm: t) {
                        out.append(OccurrenceInsert(reminder_id: r.id, dog_id: r.dog_id, occurs_at: at))
                    }}
                }
                day = cal.date(byAdding: .day, value: 1, to: day)!
            }

        case "interval":
            let step = max(1, r.interval_days ?? 1)
            var stamp = day
            while stamp <= endCap {
                for t in r.times { if let at = makeDate(stamp, hm: t) {
                    out.append(OccurrenceInsert(reminder_id: r.id, dog_id: r.dog_id, occurs_at: at))
                }}
                stamp = cal.date(byAdding: .day, value: step, to: stamp)!
            }

        case "monthly":
            let dom = cal.component(.day, from: start)
            while day <= endCap {
                if let monthHit = cal.date(bySetting: .day, value: dom, of: day) {
                    for t in r.times { if let at = makeDate(monthHit, hm: t) {
                        out.append(OccurrenceInsert(reminder_id: r.id, dog_id: r.dog_id, occurs_at: at))
                    }}
                }
                day = cal.date(byAdding: .month, value: 1, to: day)!
            }

        default: break
        }
        return out
    }

    private func minEndDate(start: Date, explicitEnd: Date?, horizonDays: Int) -> Date {
        let horizon = Calendar.current.date(byAdding: .day, value: horizonDays, to: start)!
        return min(explicitEnd ?? horizon, horizon)
    }

    private struct OccurrenceInsert: Encodable {
        let reminder_id: UUID
        let dog_id: String
        let occurs_at: Date
    }

    // Fetch occurrences in window
    func fetchReminderOccurrences(dogId: String, from: Date, to: Date) async throws -> [ReminderOccurrence] {
        try await client
            .from("reminder_occurrences")
            .select()
            .eq("dog_id", value: dogId)
            .gte("occurs_at", value: from)
            .lt("occurs_at", value: to)
            .order("occurs_at", ascending: true)
            .execute()
            .value
    }
}

extension SupabaseManager {
    /// Rebuild future occurrences for a reminder from its current definition.
    /// - Parameters:
    ///   - reminderId: The base reminder id to re-expand.
    ///   - startFrom: Delete & rebuild occurrences >= this date (defaults to start of today).
    ///   - horizonDays: How far ahead to generate.
    func reexpandReminderOccurrences(
        reminderId: UUID,
        startFrom: Date = Calendar.current.startOfDay(for: Date()),
        horizonDays: Int = 90
    ) async throws {
        // 1) Load reminder
        let r: Reminder = try await client
            .from("reminders")
            .select()
            .eq("id", value: reminderId)
            .single()
            .execute()
            .value

        // 2) Delete future occurrences for this reminder
        try await client
            .from("reminder_occurrences")
            .delete()
            .eq("reminder_id", value: reminderId)
            .gte("occurs_at", value: startFrom)
            .execute()

        // 3) Re-expand from (max(startFrom, start_date))
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = .current
        let baseStart = df.date(from: r.start_date) ?? Date()
        let effectiveStart = max(baseStart, startFrom)

        let fresh: [OccurrenceInsert] = try expandOccurrences(reminder: r, horizonDays: horizonDays)
            .compactMap { occ in
                guard occ.occurs_at >= effectiveStart else { return nil }
                return occ
            }

        if !fresh.isEmpty {
            try await client
                .from("reminder_occurrences")
                .insert(fresh)
                .execute()
        }
    }
}

// SupabaseManager.swift (in an extension)

extension SupabaseManager {
    struct CoachResp: Decodable { let answer: String }

    func askCoach(prompt: String) async throws -> String {
        let opts = FunctionInvokeOptions(body: ["prompt": prompt] as [String: String])

        // invoke returns Data
        let data: Data = try await client.functions.invoke("coach", options: opts)

        let res = try JSONDecoder().decode(CoachResp.self, from: data)
        guard !res.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "coach", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Empty answer from coach"])
        }
        return res.answer
    }
}

extension SupabaseManager {
    struct DogGoalRow: Decodable { let weekly_walks_target: Int }

    func fetchWeeklyWalksTarget(dogId: String) async throws -> Int {
        let resp = try await client
            .from("dogs")
            .select("weekly_walks_target")
            .eq("id", value: dogId)
            .limit(1)
            .execute()

        let data = resp.data
        let rows = try JSONDecoder().decode([DogGoalRow].self, from: data)
        return rows.first?.weekly_walks_target ?? WeeklyGoals.walksTarget
    }

    func updateWeeklyWalksTarget(dogId: String, target: Int) async throws {
        struct Payload: Encodable { let weekly_walks_target: Int }
        _ = try await client
            .from("dogs")
            .update(Payload(weekly_walks_target: target))
            .eq("id", value: dogId)
            .execute()
    }
}

// ===============================================================
// MARK: - Collaborators & Invites (Settings tab APIs)
// ===============================================================

extension SupabaseManager {
    // Lightweight dog model for Settings picker
    struct DogLite: Identifiable, Decodable {
        let id: String      // keep as String to match your existing dogId usage
        let name: String
    }

    
   

    // MARK: - Helpers

    /// Non-optional user id String (uses your existing auth session)
    func currentUserIdString() async throws -> String {
        guard let session = try? await client.auth.session else {
            throw NSError(domain: "Auth", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        return session.user.id.uuidString
    }




    // MARK: - Dogs I can access (owned + member)
    @MainActor
    func fetchAccessibleDogsLite() async throws -> [DogLite] {
        _ = try await currentUserIdString()
        return try await client
          .from("dogs")
          .select("id,name")
          .order("name", ascending: true)
          .execute()
          .value

    }




    // MARK: - Access check for paywall
    @MainActor
    func userHasAnyAccess() async throws -> Bool {
        _ = try await currentUserIdString()
        let count: Int = try await client
          .from("dogs")
          .select("id", head: true, count: .exact)
          .execute()
          .count ?? 0
        return count > 0

    }

}

extension SupabaseManager {
    /// Return upcoming fire times (absolute Date) for a reminder, from `startFrom` forward.
    func fetchUpcomingOccurrencesDates(reminderId: UUID,
                                       startFrom: Date = Date(),
                                       horizonDays: Int = 120,
                                       cap: Int = 64) async throws -> [Date] {
        let rows: [ReminderOccurrence] = try await client
            .from("reminder_occurrences")
            .select()
            .eq("reminder_id", value: reminderId)
            .gte("occurs_at", value: startFrom)
            .order("occurs_at", ascending: true)
            .limit(cap)
            .execute()
            .value

        return rows.map(\.occurs_at)
    }
}

// ===============================================================
// MARK: - Reminder Local Notifications Helpers
// ===============================================================
extension SupabaseManager {

    /// Persist the toggle on the reminder and then reconcile local notifications.
    @MainActor
    func setReminderNotifications(reminderId: UUID, enabled: Bool,
                                  title: String? = nil,
                                  notes: String? = nil) async {
        do {
            // 1) Persist on server
            struct Upd: Encodable { let notifications_enabled: Bool }
            try await client
                .from("reminders")
                .update(Upd(notifications_enabled: enabled))
                .eq("id", value: reminderId)
                .execute()

            // 2) Reschedule locally
            if enabled {
                await rescheduleReminderLocalNotifications(reminderId: reminderId, titleOverride: title, notesOverride: notes)
            } else {
                await NotificationManager.shared.cancelAll(for: reminderId)
            }
        } catch {
            print("❌ setReminderNotifications failed:", error.localizedDescription)
        }
    }

    /// Cancel pending and schedule fresh from upcoming occurrences.
    @MainActor
    func rescheduleReminderLocalNotifications(reminderId: UUID,
                                              titleOverride: String? = nil,
                                              notesOverride: String? = nil) async {
        await NotificationManager.shared.cancelAll(for: reminderId)

        do {
            // Load title/notes if not provided
            let r: Reminder = try await client
                .from("reminders")
                .select()
                .eq("id", value: reminderId)
                .single()
                .execute()
                .value

            guard (r.notifications_enabled ?? true) else { return }

            let fireDates = try await fetchUpcomingOccurrencesDates(reminderId: reminderId)
            guard !fireDates.isEmpty else { return }

            let title = (titleOverride ?? r.title).isEmpty ? "Reminder" : (titleOverride ?? r.title)
            let body  = (notesOverride ?? r.notes)

            await NotificationManager.shared.schedule(
                reminderId: reminderId,
                title: title,
                body: body,
                times: fireDates,
                cap: 64
            )
        } catch {
            print("❌ rescheduleReminderLocalNotifications failed:", error.localizedDescription)
        }
    }
}
extension SupabaseManager {
    /// True only if we have a valid (non-expired) session, or we can refresh it.
    func hasValidSession() async -> Bool {
        // 1) Try to read a session; if none, we’re not signed in.
        guard let s = try? await client.auth.session else {
            return false
        }

        // 2) If it hasn’t expired yet, we’re good.
        let exp = Date(timeIntervalSince1970: s.expiresAt)
        if exp > Date() { return true }

        // 3) Try to refresh once, then re-check.
        do {
            _ = try await client.auth.refreshSession()
            _ = try await client.auth.session
            return true
        } catch {
            // Don’t spam logs with decoding errors; just return false.
            return false
        }
    }
}


// MARK: - Notification the UI can listen to (e.g. dashboards/MainTab)
extension Notification.Name {
    /// Posted after join-by-code when we successfully cached a dog id.
    static let activeDogBecameAvailable = Notification.Name("activeDogBecameAvailable")
}

// MARK: - Share-code invites

extension SupabaseManager {
    private struct ShareCodeRow: Decodable {
        let share_code: String
        let expires_at: String
    }

    private struct CreateCodeParams: Encodable {
        let p_family_id: String
        let p_minutes: Int
    }

    /// Create a human-friendly share code (defaults to 7 days).
    @MainActor
    func createFamilyShareCode(familyId: String, minutes: Int = 60 * 24 * 7)
    async throws -> (code: String, expiresAt: String) {
        let params = CreateCodeParams(p_family_id: familyId, p_minutes: minutes)

        let rows: [ShareCodeRow] = try await client
            .rpc("create_family_share_code", params: params)
            .execute()
            .value

        guard let first = rows.first else {
            throw NSError(domain: "invite", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No share code returned"])
        }
        return (first.share_code, first.expires_at)
    }

    // Keep only A–F, 0–9 and '-', normalize various Unicode dashes to '-'
    private func normalizeShareCode(_ raw: String) -> String {
        // Unicode dashes we replace with ASCII '-'
        let dashSet = CharacterSet(charactersIn: "\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2212}\u{2043}")
        var ascii = ""
        ascii.reserveCapacity(raw.count)
        for scalar in raw.unicodeScalars {
            if dashSet.contains(scalar) {
                ascii.append("-")
            } else {
                ascii.unicodeScalars.append(scalar)
            }
        }

        let allowed = CharacterSet(charactersIn: "0123456789ABCDEF-")
        var outScalars = String.UnicodeScalarView()
        for u in ascii.uppercased().unicodeScalars where allowed.contains(u) {
            outScalars.append(u)
        }
        return String(outScalars)
    }

    /// First dog in a family (oldest by created_at) if any.
    func fetchFirstDogIdInFamily(_ familyId: String) async throws -> String? {
        struct Row: Decodable { let id: String }
        let rows: [Row] = try await client
            .from("dogs")
            .select("id")
            .eq("family_id", value: familyId)
            .order("created_at", ascending: true)
            .limit(1)
            .execute()
            .value
        return rows.first?.id
    }

    /// Convenience check used right after joining
    func hasDogInActiveFamily() async throws -> Bool {
        guard let fid = getActiveFamilyId() else { return false }
        struct Row: Decodable { let id: String }
        let rows: [Row] = try await client
            .from("dogs")
            .select("id")
            .eq("family_id", value: fid)
            .limit(1)
            .execute()
            .value
        return rows.first != nil
    }

    /// Join a family using a share code. Returns the joined family_id.
    @MainActor
    func acceptFamilyShareCode(_ rawCode: String) async throws -> String {
        let cleaned = normalizeShareCode(rawCode)
        guard !cleaned.isEmpty else {
            throw NSError(domain: "invite", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Please enter a code."])
        }

        // RPC RETURNS uuid → decode as scalar with .single()
        let familyId: String = try await client
            .rpc("accept_family_invite_by_code", params: ["p_share_code": cleaned])
            .single()
            .execute()
            .value

        guard !familyId.isEmpty else {
            throw NSError(domain: "invite", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid or expired code"])
        }

        // 1) Mark family active
        setActiveFamilyId(familyId)

        // 2) Clear any stale dog and immediately cache a dog from this family if one exists
        clearDogCache()
        if let did = try? await fetchFirstDogIdInFamily(familyId) {
            cacheDogId(did)
            // 3) Tell the app a dog is now available (dashboards can refresh, Setup can skip)
            NotificationCenter.default.post(name: .activeDogBecameAvailable, object: did)
        }

        return familyId
    }
}
