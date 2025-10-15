import SwiftUI
import Supabase

enum DayPart: String, CaseIterable, Identifiable {
    case morning = "Morning", afternoon = "Afternoon", night = "Night"
    var id: String { rawValue }
    var hours: [Int] {
        switch self {
        case .morning: return Array(6...11)          // 06–11
        case .afternoon: return Array(12...17)         // 17–21
        case .night:   return [18,19,20,21,22,23,0,1,2,3,4,5]    // 22–05
        }
    }
}

struct DoggieDashboardsView: View {
    @StateObject private var vm = DashboardManager.shared

    // Optional — self-fetch if nil
    var dogId: String? = nil

    @State private var resolvedDogId: String?
    @State private var loadError: String?
    @State private var isLoadingDogId = false

    // Dog profile for personalization
    @State private var profile: DogProfile?
    
  

    private let tz = TimeZone.current.identifier
    private var effectiveDogId: String? { resolvedDogId ?? dogId }

    var body: some View {
        Group {
            if let _ = effectiveDogId {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {

                        // Header — mirrors HomeView, but softer
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Good morning! 🐕")
                                .font(.system(.title2, design: .rounded)).fontWeight(.bold)
                            Text("Here’s \(profile?.name ?? "your dog")’s rhythm today")
                                .foregroundColor(.secondary)
                                .font(.system(.subheadline, design: .rounded))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                        // Quick Stats (two colorful tiles)
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Potty Stats", emoji: "✨")
                                .padding(.horizontal)

                            HStack(spacing: 16) {
                                PairCard(
                                    title: "Drink → Pee",
                                    stat: vm.drinkToPee,
                                    fallback: "—",
                                    accent: .teal,
                                    icon: "💧"
                                )
                                PairCard(
                                    title: "Eat → Poo",
                                    stat: vm.eatToPoo,
                                    fallback: "—",
                                    accent: .indigo,
                                    icon: "🍽️"
                                )
                            }
                            .padding(.horizontal)
                        }

                        // Best Times
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Peak Times", emoji: "🕒")
                                .padding(.horizontal)

                            BestTimesSection(bestTimes: vm.bestTimes, binsByEvent: vm.hourlyBins)
                                .padding(.horizontal)
                        }


                        // Routine Builder
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Routine Builder", emoji: "🧩")
                                .padding(.horizontal)

                            PromptsSection(prompts: vm.prompts) { _ in }
                                .padding(.horizontal)
                        }
                        .padding(.bottom, 24)
                    }
                    .padding(.vertical)
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("\(profile?.name ?? "Dobbie")’s Dashboard")

            } else if isLoadingDogId {
                VStack(spacing: 12) {
                    ProgressView("Loading Dobbie…")
                    Text("Fetching your dog profile")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if let err = loadError {
                VStack(spacing: 10) {
                    Text("Couldn’t load your dog").font(.headline)
                    Text(err).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Retry") { Task { await resolveDogIdIfNeeded() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                Color.clear.task { await resolveDogIdIfNeeded() }
            }
        }
        .refreshable {
            if let id = effectiveDogId {
                await vm.refresh(dogId: id, tz: tz)
                await fetchDogProfileIfNeeded(dogId: id)
            } else {
                await resolveDogIdIfNeeded()
            }
        }
        .task(id: effectiveDogId) {
            guard let id = effectiveDogId else { return }
            await vm.refresh(dogId: id, tz: tz)
            await fetchDogProfileIfNeeded(dogId: id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .activityLogsDidChange)) { _ in
            Task {
                if let id = effectiveDogId {
                    await vm.refresh(dogId: id, tz: tz)
                    await fetchDogProfileIfNeeded(dogId: id)
                } else {
                    await resolveDogIdIfNeeded()
                }
            }
        }
    }

    // MARK: - Self-fetch the ID if needed
    @MainActor
    private func resolveDogIdIfNeeded() async {
        guard resolvedDogId == nil, dogId == nil, !isLoadingDogId else { return }
        isLoadingDogId = true
        defer { isLoadingDogId = false }
        do {
            let id = try await SupabaseManager.shared.getDogId()
            if let id {
                resolvedDogId = id
                loadError = nil
            } else {
                loadError = "No dog found for the current user."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Profile fetch + model
    struct DogProfile: Decodable {
        let name: String?
        let dob: String?              // "YYYY-MM-DD"

        var ageMonths: Int? {
            guard let dob,
                  let d = DateFormatter.yearMonthDay.date(from: dob) else { return nil }
            return Calendar.current.dateComponents([.month], from: d, to: Date()).month
        }
    }

    private func fetchDogProfileIfNeeded(dogId: String) async {
        if profile != nil { return }
        let client = SupabaseManager.shared.client
        do {
            let prof: DogProfile = try await client
                .from("dogs")
                .select("name,dob")
                .eq("id", value: dogId)
                .single()
                .execute()
                .value
            await MainActor.run { self.profile = prof }
        } catch is CancellationError {
        } catch {
            print("Dog profile fetch error:", error.localizedDescription)
        }
    }
}

// ===== Helpers =====

private extension DateFormatter {
    static let yearMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}

private struct SectionHeader: View {
    let title: String
    let emoji: String
    var body: some View {
        HStack(spacing: 8) {
            Text(emoji).font(.title3)
            Text(title)
                .font(.system(.headline, design: .rounded)).fontWeight(.semibold)
        }
        .foregroundStyle(.primary)
    }
}

// ===== Subviews (simple, colorful accents, 16 radius) =====

private struct PairCard: View {
    let title: String
    let stat: PairStat?
    let fallback: String
    let accent: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title row
            HStack(spacing: 10) {
                Text(icon).font(.title3)
                    .padding(8)
                    .background(accent.opacity(0.15), in: Circle())
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
            }

            // Median only (no IQR)
            VStack(alignment: .leading, spacing: 2) {
                Text(medianText)
                    .font(.system(.title2, design: .rounded)).fontWeight(.bold)
                Text("Median")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Samples
            Text(samplesText)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .overlay(alignment: .leading) {
            // slim accent bar on the left
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 4)
                .padding(.vertical, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private var medianText: String {
        guard let m = stat?.p50_minutes else { return fallback }
        return "\(Int(round(m))) min"
    }
    private var samplesText: String {
        guard let n = stat?.samples, n > 0 else { return "No recent pairs" }
        return "Based on \(n) pairs"
    }
}

private struct BestTimesSection: View {
    let bestTimes: [BestTime]             // fallback labels/counts (currently unused)
    let binsByEvent: [String: [Int:Int]]  // event -> hour -> count

    @State private var part: DayPart = .morning
    private let tileHeight: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $part) {
                ForEach(DayPart.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)

            if bestTimes.isEmpty && binsByEvent.isEmpty {
                Text("Not enough history yet.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ],
                    spacing: 16
                ) {
                    ForEach(displayEvents(), id: \.self) { ev in
                        let bins = binsByEvent[ev] ?? [:]
                        let medianHour = weightedMedianHour(bins: bins, hours: part.hours)
                        let countInPart = part.hours.map { bins[$0] ?? 0 }.reduce(0, +)

                        BestTimeCard(
                            event: ev,
                            hour: medianHour,
                            count: countInPart,
                            fixedHeight: tileHeight,
                            titleOverride: titleFor(ev, part: part),
                            grayOut: (medianHour == nil)
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private func displayEvents() -> [String] {
        // stable 2x3 grid order
        ["pee","play","poo","sleep","walk","zoomies"]
    }

    private func titleFor(_ ev: String, part: DayPart) -> String {
        let base: String = {
            switch ev {
            case "pee":     return "Favourite Pee Time"
            case "poo":     return "Favourite Poo Time"
            case "walk":    return "Favourite Walk Time"
            case "play":    return "Favourite Play Time"
            case "zoomies": return "Favourite Zoomies Time"
            case "sleep":   return "Favourite Sleep Time"
            default:        return ev.capitalized
            }
        }()
        return "\(base) • \(part.rawValue)"
    }

    /// Weighted median within the supplied (possibly circular) hour list.
    /// IMPORTANT: keep the **given order** (don’t sort), so Night works across midnight.
    private func weightedMedianHour(bins: [Int:Int], hours: [Int]) -> Int? {
        let filtered = hours.map { ($0, bins[$0] ?? 0) }.filter { $0.1 > 0 }
        guard !filtered.isEmpty else { return nil }
        let total = filtered.reduce(0) { $0 + $1.1 }
        var cum = 0
        for (h, c) in filtered {
            cum += c
            if cum * 2 >= total { return h }
        }
        return filtered.last?.0
    }
}




private struct BestTimeCard: View {
    let event: String
    let hour: Int?                    // <- was Int
    let count: Int
    var fixedHeight: CGFloat? = nil
    var titleOverride: String? = nil
    var grayOut: Bool = false

    var body: some View {
        let accent = accentFor(event)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                iconFor(event)
                    .font(.title3)
                    .padding(6)
                    .background(accent.opacity(0.15), in: Circle())
                Text(titleOverride ?? label(for: event))
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .lineLimit(2)
            }

            Text(hourText)            // <- shows “—” when nil
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)

            Text("\(count) logs in this period")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: fixedHeight)
        .padding(12)
        .background(Color(.systemGray6).opacity(grayOut ? 0.6 : 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var hourText: String {
        guard let h = hour else { return "—" }
        let end = (h + 1) % 24
        return "\(fmt(h))–\(fmt(end))"
    }
    private func fmt(_ h: Int) -> String {
        var comps = DateComponents(); comps.hour = h
        let d = Calendar.current.date(from: comps) ?? Date()
        let f = DateFormatter(); f.dateFormat = "h a"
        return f.string(from: d).lowercased()
    }
    private func label(for ev: String) -> String {
        switch ev {
        case "pee":     return "Favourite Pee Time"
        case "poo":     return "Favourite Poo Time"
        case "walk":    return "Favourite Walk Time"
        case "play":    return "Favourite Play Time"
        case "zoomies": return "Favourite Zoomies Time"
        case "sleep":   return "Favourite Sleep Time"
        default:        return ev.capitalized
        }
    }
    private func accentFor(_ ev: String) -> Color {
        switch ev {
        case "pee":     return .teal
        case "poo":     return .indigo
        case "walk":    return .blue
        case "play":    return .orange
        case "zoomies": return .mint
        case "sleep":   return .pink
        default:        return .purple
        }
    }
    @ViewBuilder private func iconFor(_ ev: String) -> some View {
        switch ev {
        case "pee":     Text("💧")
        case "poo":     Text("💩")
        case "walk":    Text("🐾")
        case "play":    Text("🎾")
        case "zoomies": Text("⚡️")
        case "sleep":   Text("💤")
        default:        Text("✨")
        }
    }
}



private struct PromptsSection: View {
    let prompts: [RoutinePrompt]
    var onTapCTA: (RoutinePrompt) -> Void  // kept for API compatibility, not used

    var body: some View {
        VStack(spacing: 12) {
            if prompts.isEmpty {
                Text("We’ll suggest a plan once we learn Dobbie’s rhythm.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(prompts) { p in
                    let accent = accentFor(p.kind)
                    HStack(alignment: .top, spacing: 12) {
                        iconFor(p.kind)
                            .font(.title3)
                            .padding(6)
                            .background(accent.opacity(0.15), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.title)
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.semibold)
                            Text(p.suggestion)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0) // keep layout breathable; no button on the right
                    }
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                }
            }
        }
        .padding(4)
    }

    private func accentFor(_ kind: String) -> Color {
        switch kind {
        case "walk":    return .blue
        case "pee":     return .teal
        case "poo":     return .indigo
        case "summary": return .orange
        default:        return .purple
        }
    }
    @ViewBuilder private func iconFor(_ kind: String) -> some View {
        switch kind {
        case "walk":    Text("🐾")
        case "pee":     Text("💧")
        case "poo":     Text("🍽️")
        case "summary": Text("🧩")
        default:        Text("✨")
        }
    }
}


