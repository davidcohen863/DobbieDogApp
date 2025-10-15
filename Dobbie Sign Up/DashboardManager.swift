import Foundation
import Supabase
import Realtime

// MARK: - RPC return models

struct PairStat: Decodable {
    let samples: Int
    let p50_minutes: Double?
    let p25_minutes: Double?
    let p75_minutes: Double?
}

struct WalkDay: Decodable, Identifiable {
    var id: String { day }      // "YYYY-MM-DD"
    let day: String
    let minutes: Double?
    let ma7: Double?
}

/// Now expected to include: "pee","poo","walk","play","zoomies","sleep"
struct BestTime: Decodable, Identifiable {
    var id: String { event }
    let event: String
    let best_hour: Int          // 0–23 (local hour)
    let count_at_hour: Int
}

/// Optional prompts section (unchanged)
struct RoutinePrompt: Decodable, Identifiable {
    var id: String { kind + ":" + title }
    let kind: String            // "walk" | "pee" | "poo" | "summary"
    let title: String
    let suggestion: String
}

/// NEW: 24-bin histogram rows returned by `routine_hourly_counts`
struct HourBin: Decodable {
    let event: String           // same event keys as above (incl. "sleep")
    let hour: Int               // 0–23 (local hour)
    let cnt: Int
}

// MARK: - RPC param models

private struct DogTzParams: Encodable {
    let p_dog: String
    let p_tz: String
}

private struct DogTzDaysParams: Encodable {
    let p_dog: String
    let p_tz: String
    let p_days: Int
}

// MARK: - Dashboard Manager (no realtime)

@MainActor
final class DashboardManager: ObservableObject {
    static let shared = DashboardManager()

    // Published state for the widgets
    @Published var drinkToPee: PairStat?
    @Published var eatToPoo: PairStat?
    @Published var walkDays: [WalkDay] = []
    @Published var bestTimes: [BestTime] = []          // now may include "sleep"
    @Published var prompts: [RoutinePrompt] = []

    /// NEW: event → (hour → count). Used for Morning/Evening/Night tabs later.
    @Published var hourlyBins: [String: [Int: Int]] = [:]

    // Optional UI state
    @Published var showTipSheet = false
    @Published var presentTip: String? = nil

    private let client = SupabaseManager.shared.client

    // MARK: - Public API

    /// Refresh everything for a dog in a given timezone (IANA ID, e.g., "Asia/Jerusalem")
    func refresh(dogId: String, tz: String = TimeZone.current.identifier) async {
        let p  = DogTzParams(p_dog: dogId, p_tz: tz)
        let pw = DogTzDaysParams(p_dog: dogId, p_tz: tz, p_days: 30)

        // If you want a longer lookback for histograms, bump p_days here (e.g., 60)
        let ph = DogTzDaysParams(p_dog: dogId, p_tz: tz, p_days: 60)

        async let a: PairStat        = rpcSingle("routine_drink_to_pee_stats", p)
        async let b: PairStat        = rpcSingle("routine_eat_to_poo_stats",   p)
        async let c: [WalkDay]       = rpcRows("routine_walk_minutes_daily",   pw)
        async let d: [BestTime]      = rpcRows("routine_best_times",           p)  // <- should now return "sleep" too
        async let e: [RoutinePrompt] = rpcRows("routine_builder_prompts",      p)
        async let h: [HourBin]       = rpcRows("routine_hourly_counts",        ph) // NEW

        do {
            let (dp, ep, wd, bt, pr, bins) = try await (a, b, c, d, e, h)
            self.drinkToPee = dp
            self.eatToPoo   = ep
            self.walkDays   = wd
            self.bestTimes  = bt
            self.prompts    = pr
            self.mergeBins(bins) // <- populate hourlyBins
        } catch is CancellationError {
            // benign during view churn
        } catch {
            print("Dash refresh error:", error.localizedDescription)
        }
    }

    // Convenience derived labels (optional)
    var bestPeeAmPm: String? { amPm(for: "pee") }
    var bestPooAmPm: String? { amPm(for: "poo") }
    var bestSleepAmPm: String? { amPm(for: "sleep") }   // NEW helper if you need it

    // MARK: - Private helpers

    private func amPm(for event: String) -> String? {
        guard let hour = bestTimes.first(where: { $0.event == event })?.best_hour else { return nil }
        var comps = DateComponents(); comps.hour = hour
        let d = Calendar.current.date(from: comps) ?? Date()
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    /// Turn `[HourBin]` into a dictionary: event → hour → count
    private func mergeBins(_ rows: [HourBin]) {
        var out: [String: [Int: Int]] = [:]
        for r in rows {
            var m = out[r.event, default: [:]]
            m[r.hour] = r.cnt
            out[r.event] = m
        }
        self.hourlyBins = out
    }

    // Small convenience if you want to read counts safely from the view layer
    func count(for event: String, hour: Int) -> Int {
        hourlyBins[event]?[hour] ?? 0
    }

    // Generic RPC helpers
    private func rpcSingle<T: Decodable, P: Encodable>(_ name: String, _ params: P) async throws -> T {
        try await client.rpc(name, params: params).single().execute().value
    }

    private func rpcRows<T: Decodable, P: Encodable>(_ name: String, _ params: P) async throws -> T {
        try await client.rpc(name, params: params).execute().value
    }
}
