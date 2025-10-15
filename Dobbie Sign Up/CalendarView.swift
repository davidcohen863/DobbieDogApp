import SwiftUI

struct CalendarView: View {
    // MARK: - State
    @State private var selectedDate: Date = Date()
    @State private var showDayDetail = false
    @State private var activitySummary: [Date: [String]] = [:]
    @State private var reminderDays: Set<Date> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingReminderSheet = false

    // MARK: - Theme
    private let headerFont = Font.title2.weight(.bold)

    // MARK: - Calendar helpers
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    private var monthDates: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate) else { return [] }
        let firstWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: monthInterval.start))!
        let lastWeekEnd = calendar.date(byAdding: .day, value: 6, to:
            calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear],
                                                        from: calendar.date(byAdding: .day, value: -1, to: monthInterval.end)!))!
        )!
        var dates: [Date] = []
        var d = firstWeekStart
        while d <= lastWeekEnd {
            dates.append(d)
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return dates
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 12) {
                    header

                    // Weekday labels
                    HStack {
                        ForEach(calendar.shortWeekdaySymbols, id: \.self) { day in
                            Text(day.prefix(3))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal)

                    // Grid / loading
                    Group {
                        if isLoading {
                            ProgressView("Loading…").padding()
                        } else if let errorMessage {
                            Text("⚠️ \(errorMessage)").foregroundColor(.red).padding()
                        } else {
                            grid
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: isLoading)

                    Spacer(minLength: 8)
                }

                // Floating pill CTA
                VStack {
                    Spacer()
                    Button {
                        showingReminderSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.badge.fill")
                            Text("Add Reminders").fontWeight(.semibold)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(AppColors.background.ignoresSafeArea())
                        .cornerRadius(24)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                    }
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)

            // Create reminder
            .sheet(isPresented: $showingReminderSheet) {
                ReminderEditorSheet(mode: .create, isPresented: $showingReminderSheet) {
                    Task { await refreshCalendars() }
                }
            }

            // Day detail
            .navigationDestination(isPresented: $showDayDetail) {
                DayDetailView(date: selectedDate)
            }

            // Initial full load (shows spinner)
            .task { await refreshCalendars() }

            // When the visible month changes, just re-pull dots for that month
            .task(id: monthIdentity(selectedDate)) {
                await loadReminderDots() // previous task is cancelled; handled in loader
            }

            // When reminders change elsewhere, refresh ONLY the dots (fast & flicker-free)
            .onReceive(NotificationCenter.default.publisher(for: .remindersDidChange)) { _ in
                Task { await loadReminderDots() }
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        ZStack {
            HStack {
                Image(systemName: "pawprint.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .padding(.leading, 16)

                Spacer()

                Button("Today") {
                    withHaptics { withAnimation(.easeInOut) { jumpToToday() } }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.trailing, 6)

                HStack(spacing: 4) {
                    Button { withHaptics { withAnimation(.easeInOut) { changeMonth(-1) } } } label: {
                        Image(systemName: "chevron.left")
                    }
                    Button { withHaptics { withAnimation(.easeInOut) { changeMonth(1) } } } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                .padding(.trailing, 16)
            }

            Text(monthTitle(for: selectedDate)).font(headerFont)
        }
        .padding(.top, 8)
    }

    // MARK: - Grid
    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(monthDates, id: \.self) { date in
                dayCell(date)
            }
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.width < -60 {
                        withHaptics { withAnimation(.easeInOut) { changeMonth(1) } }
                    } else if value.translation.width > 60 {
                        withHaptics { withAnimation(.easeInOut) { changeMonth(-1) } }
                    }
                }
        )
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
        .id(monthIdentity(selectedDate))
    }

    private func monthIdentity(_ date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)"
    }

    private func dayCell(_ date: Date) -> some View {
        let isCurrentMonth = calendar.isDate(date, equalTo: selectedDate, toGranularity: .month)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)

        return VStack(spacing: 6) {
            ZStack {
                if isSelected {
                    Circle().fill(Color.green.opacity(0.25)).frame(width: 34, height: 34)
                }

                Text("\(calendar.component(.day, from: date))")
                    .font(.body)
                    .foregroundColor(isCurrentMonth ? .primary : .secondary.opacity(0.4))
                    .frame(width: 34, height: 34)

                if isToday {
                    Circle().stroke(Color.accentColor, lineWidth: 2).frame(width: 36, height: 36)
                }
            }
            .onTapGesture {
                selectedDate = date
                showDayDetail = true
            }

            // Activity dots
            if let types = activitySummary[calendar.startOfDay(for: date)], !types.isEmpty {
                HStack(spacing: 3) {
                    ForEach(types.prefix(3), id: \.self) { type in
                        Circle().fill(color(for: type)).frame(width: 6, height: 6)
                    }
                }
            }

            // Reminder red dot
            if reminderDays.contains(calendar.startOfDay(for: date)) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data loading
    private func refreshCalendars() async {
        isLoading = true
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadActivitySummary() }
            group.addTask { await loadReminderDots() }
        }
        isLoading = false
    }

    private func loadReminderDots() async {
        do {
            try Task.checkCancellation()

            guard let dogId = try await SupabaseManager.shared.getDogId(),
                  let monthInterval = calendar.dateInterval(of: .month, for: selectedDate) else { return }

            let start = calendar.date(byAdding: .day, value: -7, to: monthInterval.start)!
            let end   = calendar.date(byAdding: .day, value:  7, to: monthInterval.end)!

            let occ   = try await SupabaseManager.shared.fetchReminderOccurrences(dogId: dogId, from: start, to: end)
            let days  = occ.map { calendar.startOfDay(for: $0.occurs_at) }

            try Task.checkCancellation()
            await MainActor.run { reminderDays = Set(days) }
        } catch {
            if isCancellation(error) { return }
            await MainActor.run { errorMessage = "Failed to load reminders: \(error.localizedDescription)" }
        }
    }

    private func loadActivitySummary() async {
        do {
            try Task.checkCancellation()

            guard let dogId = try await SupabaseManager.shared.getDogId() else {
                await MainActor.run { errorMessage = "No dog found" }
                return
            }

            let cal = Calendar.current
            let start = cal.date(byAdding: .day, value: -30, to: Date())!
            let logs = try await SupabaseManager.shared.fetchActivityLogs(dogId: dogId, from: start, to: Date())

            try Task.checkCancellation()

            // Group by day for the color dots
            let grouped = Dictionary(grouping: logs) { log in
                cal.startOfDay(for: log.timestamp)
            }

            await MainActor.run {
                activitySummary = grouped.mapValues { Array(Set($0.map { $0.event_type })) }
            }
        } catch {
            if isCancellation(error) { return }
            await MainActor.run { errorMessage = "Failed to load logs: \(error.localizedDescription)" }
        }
    }

    // Treat benign cancellations as non-errors
    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }   // -999
        if ns.domain == NSPOSIXErrorDomain && ns.code == 89 { return true }                  // Operation canceled
        let msg = ns.localizedDescription.lowercased()
        return msg.contains("cancelled") || msg.contains("canceled")
    }

    // MARK: - Helpers
    private func jumpToToday() { selectedDate = Date() }

    private func changeMonth(_ offset: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: offset, to: selectedDate) {
            selectedDate = newMonth
        }
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }

    private func color(for type: String) -> Color {
        switch type.lowercased() {
        case "pee":     return .blue
        case "poo":     return .brown
        case "walk":    return .green
        case "eat":     return .orange
        case "play":    return .yellow
        case "sleep":   return .purple
        case "drink":   return .teal      // or .cyan if you prefer
        case "zoomies": return .pink
        default:        return .gray
        }
    }


    private func withHaptics(_ block: () -> Void) {
        #if os(iOS)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        #endif
        block()
    }
} // <-- ONLY closing brace for CalendarView
