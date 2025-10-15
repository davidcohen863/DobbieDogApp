import SwiftUI
import Supabase
import Charts

struct HomeView: View {
    @Binding var isSignedIn: Bool
    var dogName: String

    // ✅ Match SupabaseManager.ActivityLog type
    @State private var todaysLogs: [SupabaseManager.ActivityLog] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editingLog: SupabaseManager.ActivityLog? = nil
    @State private var showingEditor = false
    @State private var showWalkEditor = false
    @State private var activeDogIdForWalk: String? = nil
    @State private var showSleepEditor = false
    @State private var activeDogIdForSleep: String? = nil

    // === Today’s Reminders state ===
    @State private var todaysReminders: [SupabaseManager.ReminderOccurrenceWithTitle] = []
    @State private var isLoadingReminders = false
    @State private var remindersError: String?
    @State private var editingReminderId: UUID? = nil
    @State private var showingReminderEditor = false

    private var shortTimeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        f.timeZone = .current
        return f
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Greeting Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Good morning! 🐕")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Let's take care of \(dogName) today")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                // Quick Log Buttons
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quick Log ✨")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            QuickLogIcon(title: "Pee",  emoji: "💧") { completeQuick("pee") }
                            QuickLogIcon(title: "Poo",  emoji: "💩") { completeQuick("poo") }
                            QuickLogIcon(title: "Feed", emoji: "🍖") { completeQuick("eat") }
                            QuickLogIcon(title: "Walk", emoji: "🐾") { completeQuick("walk") }
                        }

                        HStack(spacing: 16) {
                            QuickLogIcon(title: "Play",    emoji: "🎾") { completeQuick("play") }
                            QuickLogIcon(title: "Sleep",   emoji: "😴") { completeQuick("sleep") }
                            QuickLogIcon(title: "Drink",   emoji: "🫗") { completeQuick("drink") }
                            QuickLogIcon(title: "Zoomies", emoji: "⚡️") { completeQuick("zoomies") }
                        }
                    }

                    .padding(.horizontal)
                }

                // === Today’s Reminders ===
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Today’s Reminders")
                            .font(.headline)
                        Spacer()
                        if isLoadingReminders { ProgressView().scaleEffect(0.8) }
                    }
                    .padding(.horizontal)

                    if let err = remindersError {
                        Text("⚠️ \(err)")
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    } else if todaysReminders.isEmpty {
                        Text("No reminders for today.")
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(todaysReminders) { r in
                                HomeReminderRow(
                                    occurrence: r,
                                    timeFormatter: shortTimeFormatter,
                                    onToggle: { Task { await toggleOccurrence(r) } },
                                    onEdit: {
                                        editingReminderId = r.reminder_id
                                        showingReminderEditor = true
                                    },
                                    onDelete: { Task { await deleteOccurrence(r) } }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // ✅ Today's Logged Activities
                VStack(alignment: .leading, spacing: 12) {
                    Text("Today's Activity 🗓️")
                        .font(.headline)
                        .padding(.horizontal)

                    if isLoading {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if let error = errorMessage {
                        Text("⚠️ \(error)")
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    } else if todaysLogs.isEmpty {
                        Text("No activities logged yet today.")
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                    } else {
                        ForEach(todaysLogs, id: \.id) { log in
                            ActivityCard(
                                log: log,
                                onEdit: {
                                    editingLog = log
                                    showingEditor = true
                                },
                                onDelete: {
                                    Task { await deleteLog(log) }
                                }
                            )
                            .onTapGesture {
                                editingLog = log
                                showingEditor = true
                            }
                        }
                    }
                }

                // Insights Section
                InsightsSection(dogName: dogName)

                // Log Out
                Button("Log Out") {
                    Task {
                        await SupabaseManager.shared.signOut()
                        DispatchQueue.main.async { isSignedIn = false }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.top, 40)
                .padding(.horizontal)
            }
            .padding(.vertical)
#if DEBUG
Button("Test Notification in 5s") {
    Task { await NotificationManager.shared.scheduleDebugIn(seconds: 5) }
}
Button("List Pending") {
    Task { await NotificationManager.shared.printPending() }
}
Button("Clear Pending") {
    Task { await NotificationManager.shared.removeAllPending() }
}
#endif

        }
        
        
        
        // Kick off both loads
        .task { await loadTodaysLogs() }
        .task { await loadTodaysReminders() }

        // Edit activity sheets (unchanged)
        .sheet(isPresented: $showingEditor) {
            if let editingLog = editingLog {
                switch editingLog.event_type.lowercased() {
                case "walk":
                    WalkEditView(
                        dogId: editingLog.dog_id,
                        existingLog: editingLog,
                        onSaved: { Task { await loadTodaysLogs(); await InsightsData.shared.refreshFromSupabase() } },
                        onDeleted: { Task { await deleteLog(editingLog); await loadTodaysLogs(); await InsightsData.shared.refreshFromSupabase() } }
                    )
                case "sleep":
                    SleepEditView(
                        dogId: editingLog.dog_id,
                        existingLog: editingLog,
                        onSaved: { Task { await loadTodaysLogs(); await InsightsData.shared.refreshFromSupabase() } },
                        onDeleted: { Task { await deleteLog(editingLog); await loadTodaysLogs(); await InsightsData.shared.refreshFromSupabase() } }
                    )
                default:
                    EditActivityView(
                        log: editingLog,
                        isPresented: $showingEditor,
                        onSave: { updated in
                            Task { await updateLog(updated); await loadTodaysLogs(); await InsightsData.shared.refreshFromSupabase() }
                        },
                        onDelete: { deleted in
                            Task { await deleteLog(deleted); await loadTodaysLogs(); await InsightsData.shared.refreshFromSupabase() }
                        }
                    )
                }
            }
        }

        // Sheet for editing a reminder (reuses ReminderEditorSheet)
        .sheet(isPresented: $showingReminderEditor, onDismiss: {
            Task { await loadTodaysReminders() }
        }) {
            if let rid = editingReminderId {
                ReminderEditorSheet(
                    mode: .edit(reminderId: rid),
                    isPresented: $showingReminderEditor
                ) {
                    // Editor already posts .remindersDidChange, but we refresh locally too
                    Task { await loadTodaysReminders() }
                }
            }
        }

        // Sheet for creating a new Walk (from Quick Log)
        .sheet(isPresented: $showWalkEditor, onDismiss: {
            Task {
                await loadTodaysLogs()
                await InsightsData.shared.refreshFromSupabase()
            }
        }) {
            if let dogId = activeDogIdForWalk {
                WalkEditView(
                    dogId: dogId,
                    existingLog: nil,                 // create mode
                    onSaved: {
                        Task {
                            await loadTodaysLogs()
                            await InsightsData.shared.refreshFromSupabase()
                        }
                    }
                )
            } else {
                // Fallback (shouldn't happen): dismiss if no dogId
                Color.clear.onAppear { showWalkEditor = false }
            }
        }

        // Sheet for creating a new Sleep (from Quick Log)
        .sheet(isPresented: $showSleepEditor, onDismiss: {
            Task {
                await loadTodaysLogs()
                await InsightsData.shared.refreshFromSupabase()
            }
        }) {
            if let dogId = activeDogIdForSleep {
                SleepEditView(
                    dogId: dogId,
                    existingLog: nil,
                    onSaved: {
                        Task {
                            await loadTodaysLogs()
                            await InsightsData.shared.refreshFromSupabase()
                        }
                    }
                )
            } else {
                Color.clear.onAppear { showSleepEditor = false }
            }
        }

        // Keep reminders in sync with Calendar/DayDetail changes
        .onReceive(NotificationCenter.default.publisher(for: .remindersDidChange)) { _ in
            Task { await loadTodaysReminders() }
        }
    }

    // MARK: - Quick Logging Logic
    private func completeQuick(_ type: String) {
        let now = Date()
        Task {
            guard let dogId = try? await SupabaseManager.shared.getDogId(),
                  !dogId.isEmpty else {
                print("❌ dogId not found — skipping quick log.")
                return
            }

            if type == "walk" {
                await MainActor.run {
                    self.activeDogIdForWalk = dogId
                    self.showWalkEditor = true
                }
                return
            }

            if type == "sleep" {
                await MainActor.run {
                    self.activeDogIdForSleep = dogId
                    self.showSleepEditor = true
                }
                return
            }

            do {
                // 1) Insert and get the created row (with id)
                let created = try await SupabaseManager.shared.createActivity(
                    dogId: dogId,
                    eventType: type,
                    at: now
                )

                // 2) Immediately show the editor for this new log
                await MainActor.run {
                    self.editingLog = created
                    self.showingEditor = true
                }

                // 3) Refresh lists/insights
                await loadTodaysLogs()
                await InsightsData.shared.refreshFromSupabase()
            } catch {
                print("❌ Quick insert failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Reminders helpers (Today)
    private func loadTodaysReminders() async {
        isLoadingReminders = true
        defer { isLoadingReminders = false }

        do {
            guard let dogId = try await SupabaseManager.shared.getDogId() else { return }
            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            let end   = cal.date(byAdding: .day, value: 1, to: start)!

            let occ = try await SupabaseManager.shared.fetchReminderOccurrencesWithTitle(
                dogId: dogId,
                from: start,
                to: end
            )

            await MainActor.run {
                todaysReminders = occ.sorted { $0.occurs_at < $1.occurs_at }
                remindersError = nil
            }
        } catch {
            await MainActor.run { remindersError = error.localizedDescription }
        }
    }

    private func toggleOccurrence(_ occ: SupabaseManager.ReminderOccurrenceWithTitle) async {
        do {
            struct Update: Encodable {
                let status: String
                let completed_at: Date?
            }
            let markDone = (occ.status != "done")
            let payload = Update(status: markDone ? "done" : "pending",
                                 completed_at: markDone ? Date() : nil)

            try await SupabaseManager.shared.client
                .from("reminder_occurrences")
                .update(payload)
                .eq("id", value: occ.id)
                .execute()

            await MainActor.run {
                NotificationCenter.default.post(name: .remindersDidChange, object: nil)
            }
            await loadTodaysReminders()
        } catch {
            print("❌ toggleOccurrence failed:", error.localizedDescription)
        }
    }

    private func deleteOccurrence(_ occ: SupabaseManager.ReminderOccurrenceWithTitle) async {
        do {
            try await SupabaseManager.shared.client
                .from("reminder_occurrences")
                .delete()
                .eq("id", value: occ.id)
                .execute()

            await MainActor.run {
                NotificationCenter.default.post(name: .remindersDidChange, object: nil)
            }
            await loadTodaysReminders()
        } catch {
            print("❌ deleteOccurrence failed:", error.localizedDescription)
        }
    }

    // MARK: - CRUD Functions (Activities)
    private func loadTodaysLogs() async {
        isLoading = true
        do {
            guard let dogId = try await SupabaseManager.shared.getDogId() else { return }
            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            let end = cal.date(byAdding: .day, value: 1, to: start)!

            let logs = try await SupabaseManager.shared.fetchActivityLogs(
                dogId: dogId,
                from: start,
                to: end
            )

            await MainActor.run {
                todaysLogs = logs.sorted(by: { $0.timestamp > $1.timestamp })
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load logs: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func updateLog(_ updated: SupabaseManager.ActivityLog) async {
        do {
            struct ActivityLogUpdate: Encodable {
                let event_type: String
                let timestamp: String
                let notes: String?
            }

            let payload = ActivityLogUpdate(
                event_type: updated.event_type.lowercased(),
                timestamp: updated.timestamp.supabaseTimestampUTC,
                notes: updated.notes,
            )

            try await SupabaseManager.shared.client
                .from("activity_logs")
                .update(payload)
                .eq("id", value: updated.id)
                .execute()

            await loadTodaysLogs()
            await InsightsData.shared.refreshFromSupabase()
        } catch {
            print("❌ Update failed:", error.localizedDescription)
        }
    }


    private func deleteLog(_ log: SupabaseManager.ActivityLog) async {
        await SupabaseManager.shared.deleteLog(log)
        await loadTodaysLogs()
        await InsightsData.shared.refreshFromSupabase()
    }
}

// MARK: - Components

struct QuickLogIcon: View {
    let title: String
    let emoji: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(emoji).font(.largeTitle)
                Text(title).font(.footnote).foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
    }
}


// MARK: - Activity Card

struct ActivityCard: View {
    let log: SupabaseManager.ActivityLog
    var onEdit: () -> Void
    var onDelete: () -> Void

    private func emoji(for type: String) -> String {
        switch type.lowercased() {
        case "pee": return "💧"
        case "poo": return "💩"
        case "walk": return "🐾"
        case "eat": return "🍖"
        case "play": return "🎾"
        case "sleep": return "😴"
        case "drink": return "🫗"
        case "zoomies": return "⚡️"
        default: return "📋"
        }
    }


    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

    var body: some View {
        HStack {
            Text(emoji(for: log.event_type))
                .font(.largeTitle)
                .frame(width: 40)
            VStack(alignment: .leading) {
                Text(log.event_type.capitalized)
                    .font(.headline)
                Text(timeFormatter.string(from: log.timestamp))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            }
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(AppColors.background)
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// === Reminders Row for Home ===
private struct HomeReminderRow: View {
    let occurrence: SupabaseManager.ReminderOccurrenceWithTitle
    let timeFormatter: DateFormatter
    var onToggle: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var titleText: String {
        (occurrence.reminders?.title?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Reminder"
    }

    var body: some View {
        let isDone = (occurrence.status == "done")

        HStack(spacing: 12) {
            Text("🔔").font(.largeTitle).frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .fontWeight(.semibold)
                    .strikethrough(isDone, color: .secondary)
                    .foregroundColor(isDone ? .secondary : .primary)

                Text(timeFormatter.string(from: occurrence.occurs_at))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            Spacer()

            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isDone ? .green : .secondary)
            }
            Button(action: onEdit)  { Image(systemName: "pencil").foregroundColor(.blue) }
            Button(action: onDelete){ Image(systemName: "trash").foregroundColor(.red)  }
        }
        .padding()
        .background(Color.red.opacity(0.10))
        .cornerRadius(12)
        .padding(.horizontal, 0)
    }
}

// MARK: - Utility (UTC Timestamp Helper)
extension Date {
    var supabaseTimestampUTC: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // Always UTC
        return formatter.string(from: self)
    }
}
