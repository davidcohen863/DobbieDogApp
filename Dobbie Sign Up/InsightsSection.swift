import SwiftUI
import Charts
import UIKit

// MARK: - Global Haptics
func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    let gen = UINotificationFeedbackGenerator()
    gen.prepare()
    gen.notificationOccurred(type)
}

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
    let gen = UIImpactFeedbackGenerator(style: style)
    gen.prepare()
    gen.impactOccurred()
}

struct InsightsSection: View {
    let dogName: String
    @ObservedObject var data = InsightsData.shared
    @State private var expanded: InsightKind?
    @State private var period: Period = .week
    @State private var showConfetti = false
    @State private var progress: Double = 0

    // NEW: live, per-dog goal with a safe default
    @State private var weeklyWalkTarget: Int = WeeklyGoals.walksTarget
    @State private var showEditGoal = false
    @State private var isLoadingGoal = false
    @State private var goalError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                Text("📊 \(dogName)'s Week")
                    .font(.title3).fontWeight(.bold)
                Spacer()
               

                // NEW: edit button
                Button {
                    showEditGoal = true
                } label: {
                    Image(systemName: "target")
                        .imageScale(.medium)
                        .padding(8)
                }
                .accessibilityLabel("Edit weekly goal")
            }
            .padding(.horizontal)

            // Pawesome Meter now uses weeklyWalkTarget
            PawesomeMeter(
                progress: weeklyWalkProgress(),
                weeklyTarget: weeklyWalkTarget,
                isSavingTarget: isLoadingGoal,               // NEW
                onChangeTarget: { newVal in                  // NEW
                    Task { await saveWeeklyGoal(newVal) }    // persist to Supabase
                },
                onCelebrate: {
                    haptic(.success)
                    showConfetti = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showConfetti = false }
                },
                streakText: "Week \(Calendar.current.component(.weekOfYear, from: Date())) • keep the streak!"
            )


            .padding(.horizontal)
            .padding(.bottom, 4)

            // Nudges use weeklyWalkTarget
            NudgeRow(
                progress: weeklyWalkProgress(),
                target: weeklyWalkTarget
            )
            .padding(.horizontal)

            // … your cards unchanged …
            VStack(spacing: 16) {
                WalkTrendsCard(walkData: data.walkData) { expanded = .walks }
                PottyTrendsCard(pottyData: data.pottyData) { expanded = .potty }
            }

            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .sheet(item: $expanded) { kind in
            InsightDetailSheet(kind: kind)
        }
        .overlay(ConfettiView(trigger: $showConfetti).allowsHitTesting(false))
        .task {
            // load insights
            await data.refreshFromSupabase()
        }
        .task {
            // NEW: load goal from Supabase
            await loadWeeklyGoal()
        }
    }

    private func weeklyWalkProgress() -> Double {
        let total = data.walkData.reduce(0) { $0 + $1.count }
        return min(1.0, Double(total) / Double(weeklyWalkTarget))
    }

    // NEW: goal I/O
    private func loadWeeklyGoal() async {
        isLoadingGoal = true
        defer { isLoadingGoal = false }
        do {
            guard let dogId = try await SupabaseManager.shared.getDogId() else { return }
            let target = try await SupabaseManager.shared.fetchWeeklyWalksTarget(dogId: dogId)
            await MainActor.run {
                self.weeklyWalkTarget = max(1, target) // avoid 0
                self.goalError = nil
            }
        } catch {
            await MainActor.run {
                self.weeklyWalkTarget = WeeklyGoals.walksTarget // fallback
                self.goalError = error.localizedDescription
            }
        }
    }

    private func saveWeeklyGoal(_ newTarget: Int) async {
        isLoadingGoal = true
        defer { isLoadingGoal = false }
        do {
            guard let dogId = try await SupabaseManager.shared.getDogId() else { return }
            try await SupabaseManager.shared.updateWeeklyWalksTarget(dogId: dogId, target: newTarget)
            await MainActor.run {
                self.weeklyWalkTarget = newTarget
                self.showEditGoal = false
                self.goalError = nil
                haptic(.success)
            }
        } catch {
            await MainActor.run { self.goalError = error.localizedDescription }
        }
    }
}

    
private struct EditWeeklyGoalSheet: View {
    @State private var value: Int
    let isLoading: Bool
    let error: String?
    let onSave: (Int) -> Void

    init(current: Int, isLoading: Bool, error: String?, onSave: @escaping (Int) -> Void) {
        self._value = State(initialValue: max(1, current))
        self.isLoading = isLoading
        self.error = error
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Weekly Walk Goal")) {
                    Stepper(value: $value, in: 1...70, step: 1) {
                        Text("\(value) walks / week")
                    }
                }
                if let e = error {
                    Section { Text("⚠️ \(e)").foregroundColor(.red) }
                }
            }
            .navigationTitle("Edit Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isLoading ? "Saving…" : "Save") {
                        onSave(value)
                    }
                    .disabled(isLoading)
                }
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
}

    
  
   
    
  
    
    // ====================================================
    // MARK: - Walk / Activity / Potty Cards
    // ====================================================
    
struct WalkTrendsCard: View {
    let walkData: [WalkData]
    var onExpand: () -> Void
    @State private var animate = false

    var body: some View {
        InsightStatCard(
            title: "🐾 Walk Trends",
            subtitle: "This week’s pace",       // <- fixed weekly
            icon: "figure.walk.motion",
            tint: .green.opacity(0.2)
        ) {
            Chart(walkData) { day in
                BarMark(
                    x: .value("Day", day.day),
                    y: .value("Walks", animate ? day.count : 0)
                )
                .foregroundStyle(
                    LinearGradient(colors: [.green, .mint], startPoint: .top, endPoint: .bottom)
                )
                .cornerRadius(6)
                .annotation(position: .top) {
                    if animate {
                        Text("\(day.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .chartYAxis(.hidden)
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: animate)
            .onAppear { animate = true }
        }
        .onTapGesture { onExpand() }
    }
}


struct PottyTrendsCard: View {
    let pottyData: [PottyData]
    var onExpand: () -> Void
    @State private var animate = false

    var body: some View {
        InsightStatCard(
            title: "🚽 Potty Tracker",
            subtitle: "This week’s consistency",   // <- fixed weekly
            icon: "drop.fill",
            tint: .yellow.opacity(0.25)
        ) {
            Chart(pottyData) { entry in
                BarMark(
                    x: .value("Day", entry.day),
                    y: .value("Count", animate ? entry.count : 0)
                )
                .foregroundStyle(
                    entry.type == "Pee"
                    ? LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                )
                .cornerRadius(6)
            }
            .chartLegend(position: .top, alignment: .leading)
            .onAppear { animate = true }
        }
        .onTapGesture { onExpand() }
    }
}

    
    // ====================================================
    // MARK: - Supporting UI
    // ====================================================
    
/// Default weekly targets (used by PawesomeMeter, Nudges, etc.)


    
    // Same PawesomeMeter, ProgressRing, NudgeRow, BadgeStrip, BadgeTile, ConfettiView, InsightStatCard as before
    // ✅ but without re-defining models (Badge, Period, WeeklyGoals)
    
    // Detail Sheet
    struct InsightDetailSheet: View {
        let kind: InsightKind
        var body: some View {
            VStack {
                Text("🐶 Detail for \(kind.id)").font(.largeTitle)
                Spacer()
            }.padding()
        }
    }
    // MARK: - Pawesome Meter
struct PawesomeMeter: View {
    let progress: Double
    let weeklyTarget: Int
    let isSavingTarget: Bool              // NEW
    let onChangeTarget: (Int) -> Void     // NEW
    let onCelebrate: () -> Void
    let streakText: String

    @State private var animatedProgress: Double = 0

    var body: some View {
        HStack(spacing: 16) {
            ProgressRing(progress: animatedProgress, size: 86, startColor: .green, endColor: .mint, emoji: "🐾")
                .onChange(of: progress) { _, newValue in
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { animatedProgress = newValue }
                    let thresholds: [Double] = [0.25, 0.5, 0.75, 1.0]
                    if thresholds.contains(where: { abs(newValue - $0) < 0.02 }) { onCelebrate() }
                }
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { animatedProgress = progress }
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(headline(progress: progress, target: weeklyTarget))
                    .font(.headline)
                Text(streakText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // --- Inline goal control (+ / -) ---
                // --- Inline goal control (badge, then − / + on the right) ---
                HStack(spacing: 8) {
                    Text("Goal:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // Badge
                    Text("\(weeklyTarget)/week")
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(8)

                    // − button (to the right of the badge)
                    Button {
                        guard weeklyTarget < 70 else { return }
                        haptic(.light)
                        onChangeTarget(weeklyTarget + 1)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Increase weekly goal")
                    .disabled(isSavingTarget || weeklyTarget >= 70)
                    
                    Button {
                        guard weeklyTarget > 1 else { return }
                        haptic(.light)
                        onChangeTarget(weeklyTarget - 1)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .accessibilityLabel("Decrease weekly goal")
                    .disabled(isSavingTarget || weeklyTarget <= 1)


                    if isSavingTarget {
                        ProgressView().scaleEffect(0.6)
                    }
                }

            }
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private func headline(progress: Double, target: Int) -> String {
        let done = Int(round(progress * Double(target)))
        if done >= target { return "🎉 Weekly goal crushed!" }
        if target - done == 1 { return "So close! 1 walk to your goal" }
        return "Great pace! \(done)/\(target) walks this week"
    }
}

    
    // MARK: - Progress Ring
    struct ProgressRing: View {
        let progress: Double
        let size: CGFloat
        let startColor: Color
        let endColor: Color
        let emoji: String
        
        var body: some View {
            ZStack {
                Circle().stroke(lineWidth: 10).opacity(0.15).foregroundColor(endColor)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(gradient: Gradient(colors: [startColor, endColor]), center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(emoji).font(.title2)
            }
            .frame(width: size, height: size)
        }
    }
    
    // MARK: - Nudge Row
    struct NudgeRow: View {
        let progress: Double
        let target: Int
        
        
        var body: some View {
            let done = Int(round(progress * Double(target)))
            let remaining = max(0, target - done)
            let copy: String = (remaining == 0) ? "🐶 Dobbie is doing amazing this week!" :
            (remaining == 1 ? "You’re one walk away from your weekly goal!" :
                "Nice! \(remaining) to go this week.")
            
            HStack(spacing: 12) {
                Text(copy).font(.subheadline)
                Spacer()
            }
            .padding(12)
            .background(Color.green.opacity(0.08))
            .cornerRadius(12)
        }
    }
    
    
    // MARK: - Confetti
    struct ConfettiView: View {
        @Binding var trigger: Bool
        let emojis = ["🎉","✨","🎊","🐶","💚"]
        var body: some View {
            ZStack {
                ForEach(0..<15, id: \.self) { i in
                    Text(emojis[i % emojis.count])
                        .opacity(trigger ? 1 : 0)
                        .offset(x: trigger ? CGFloat(Int.random(in: -140...140)) : 0,
                                y: trigger ? CGFloat(Int.random(in: 50...220)) : -30)
                        .rotationEffect(.degrees(trigger ? Double.random(in: -40...40) : 0))
                        .animation(.spring(response: 0.9, dampingFraction: 0.7).delay(Double(i) * 0.02), value: trigger)
                }
            }
        }
    }
    
    // MARK: - Generic Card
    struct InsightStatCard<Content: View>: View {
        let title: String
        let subtitle: String
        let icon: String
        let tint: Color
        let content: Content
        
        init(title: String, subtitle: String, icon: String, tint: Color, @ViewBuilder content: () -> Content) {
            self.title = title
            self.subtitle = subtitle
            self.icon = icon
            self.tint = tint
            self.content = content()
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(tint).frame(width: 36, height: 36)
                        Image(systemName: icon).foregroundColor(.primary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                
                // Chart
                content
                    .frame(height: 120) // ⬅️ reduced height
            }
            .padding()
            .frame(maxWidth: .infinity) // ⬅️ no fixed minHeight
            .background(
                LinearGradient(colors: [tint.opacity(0.35), Color(.systemBackground)],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            )
            .cornerRadius(18)
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
    }
    

        
    

