import SwiftUI

struct DayDetailView: View {
    enum Tab: String, CaseIterable, Identifiable { case reminders = "Reminders", activities = "Activities"; var id: String { rawValue } }

    let date: Date
    @State private var activities: [SupabaseManager.ActivityLog] = []
    @State private var reminders: [SupabaseManager.ReminderOccurrenceWithTitle] = []

    // Reminder editing
    @State private var editingReminderId: UUID? = nil
    @State private var showingReminderEditor = false

    // Activity editing
    @State private var editingLog: SupabaseManager.ActivityLog? = nil
    @State private var showingEditor = false

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab: Tab = .reminders

    private var headerFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeZone = .current
        return f
    }
    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        f.timeZone = .current
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headerFormatter.string(from: date))
                .font(.headline)
                .padding(.horizontal)

            Picker("", selection: $selectedTab) {
                Text(Tab.reminders.rawValue).tag(Tab.reminders)
                Text(Tab.activities.rawValue).tag(Tab.activities)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let errorMessage {
                Text("⚠️ \(errorMessage)").foregroundColor(.red).padding()
            } else {
                Group {
                    switch selectedTab {
                    case .reminders:  remindersList
                    case .activities: activitiesList
                    }
                }
                .animation(.easeInOut, value: selectedTab)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }

        // Activity editor
        .sheet(isPresented: $showingEditor) {
            if let editingLog {
                EditActivityView(
                    log: editingLog,
                    isPresented: $showingEditor,
                    onSave: { updated in Task { await updateLog(updated) } },
                    onDelete: { deleted in Task { await deleteLog(deleted) } }
                )
            }
        }

        // Reminder editor (same UI as Add – using ReminderEditorSheet in .edit mode)
        .sheet(isPresented: $showingReminderEditor, onDismiss: { Task { await loadData() } }) {
            if let rid = editingReminderId {
                ReminderEditorSheet(
                    mode: .edit(reminderId: rid),
                    isPresented: $showingReminderEditor
                ) {
                    Task { await loadData() }
                }
            }
        }
    }

    // MARK: - Lists
    private var remindersList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if reminders.isEmpty {
                    Text("No reminders for this day.")
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                        .padding(.top, 8)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(reminders) { r in
                            ReminderRow(
                                occurrence: r,
                                timeFormatter: timeFormatter,
                                onToggle:   { Task { await toggleOccurrence(r) } },
                                onEdit:     { editingReminderId = r.reminder_id; showingReminderEditor = true },
                                onDelete:   { Task { await deleteOccurrence(r) } }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .refreshable { await loadData() }
        }
    }

    private var activitiesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if activities.isEmpty {
                    Text("No activities logged for this day.")
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                        .padding(.top, 8)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(activities, id: \.id) { log in
                            ActivityRow(
                                log: log,
                                timeFormatter: timeFormatter,
                                onEdit:   { editingLog = log; showingEditor = true },
                                onDelete: { Task { await deleteLog(log) } }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .refreshable { await loadData() }
        }
    }

    // MARK: - Load activities + reminders
    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let dogId = try await SupabaseManager.shared.getDogId() else {
                errorMessage = "No dog found"; return
            }

            let cal = Calendar.current
            let startOfDay = cal.startOfDay(for: date)
            let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!

            async let logsTask: [SupabaseManager.ActivityLog] =
                SupabaseManager.shared.fetchActivityLogs(dogId: dogId, from: startOfDay, to: endOfDay)
            async let remsTask: [SupabaseManager.ReminderOccurrenceWithTitle] =
                SupabaseManager.shared.fetchReminderOccurrencesWithTitle(dogId: dogId, from: startOfDay, to: endOfDay)

            let (logs, rems) = try await (logsTask, remsTask)

            await MainActor.run {
                activities = logs.sorted { $0.timestamp > $1.timestamp }
                reminders = rems
                errorMessage = nil
                selectedTab = reminders.isEmpty ? .activities : .reminders
            }
        } catch {
            await MainActor.run { errorMessage = "Failed to load: \(error.localizedDescription)" }
        }
    }

    // MARK: - Update/Delete Activity
    private func updateLog(_ updated: SupabaseManager.ActivityLog) async {
        do {
            struct ActivityLogUpdate: Codable {
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

            await loadData()
            await InsightsData.shared.refreshFromSupabase()
        } catch {
            print("❌ Update failed:", error.localizedDescription)
        }
    }

    private func deleteLog(_ log: SupabaseManager.ActivityLog) async {
        do {
            try await SupabaseManager.shared.client
                .from("activity_logs")
                .delete()
                .eq("id", value: log.id)
                .execute()
            await loadData()
            await InsightsData.shared.refreshFromSupabase()
        } catch {
            print("❌ Delete failed:", error.localizedDescription)
        }
    }

    // MARK: - Occurrence actions (toggle status / delete one)
    private func toggleOccurrence(_ occ: SupabaseManager.ReminderOccurrenceWithTitle) async {
        do {
            // Using String status in your model
            let newStatus = (occ.status == "done") ? "pending" : "done"
            struct UpdateStatus: Encodable { let status: String }
            try await SupabaseManager.shared.client
                .from("reminder_occurrences")
                .update(UpdateStatus(status: newStatus))
                .eq("id", value: occ.id)
                .execute()
            await loadData()
        } catch {
            print("❌ toggle occurrence failed:", error.localizedDescription)
        }
    }

    private func deleteOccurrence(_ occ: SupabaseManager.ReminderOccurrenceWithTitle) async {
        do {
            try await SupabaseManager.shared.client
                .from("reminder_occurrences")
                .delete()
                .eq("id", value: occ.id)
                .execute()
            await loadData()
        } catch {
            print("❌ delete occurrence failed:", error.localizedDescription)
        }
    }

    // MARK: - Delete whole Reminder (kept for completeness)
    private func deleteReminder(reminderId: UUID) async {
        do {
            _ = try? await SupabaseManager.shared.client
                .from("reminder_occurrences")
                .delete()
                .eq("reminder_id", value: reminderId)
                .execute()

            try await SupabaseManager.shared.client
                .from("reminders")
                .delete()
                .eq("id", value: reminderId)
                .execute()

            await loadData()
        } catch {
            print("❌ Delete reminder failed:", error.localizedDescription)
        }
    }

    // MARK: - Activity Row
    struct ActivityRow: View {
        let log: SupabaseManager.ActivityLog
        let timeFormatter: DateFormatter
        var onEdit: () -> Void
        var onDelete: () -> Void

        private func emoji(for type: String) -> String {
            switch type.lowercased() {
            case "pee":     return "💧"
            case "poo":     return "💩"
            case "walk":    return "🐾"
            case "eat":     return "🍖"
            case "play":    return "🎾"
            case "sleep":   return "😴"
            case "drink":   return "🫗"     // NEW
            case "zoomies": return "⚡️"     // NEW
            default:        return "📋"
            }
        }

        private func color(for type: String) -> Color {
            switch type.lowercased() {
            case "pee":     return .blue.opacity(0.15)
            case "poo":     return .brown.opacity(0.15)
            case "walk":    return .green.opacity(0.15)
            case "eat":     return .orange.opacity(0.15)
            case "play":    return .yellow.opacity(0.15)
            case "sleep":   return .purple.opacity(0.15)
            case "drink":   return .teal.opacity(0.15)     // NEW
            case "zoomies": return .pink.opacity(0.15)     // NEW
            default:        return .gray.opacity(0.1)
            }
        }


        var body: some View {
            HStack(spacing: 12) {
                Text(emoji(for: log.event_type))
                    .font(.largeTitle)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(log.event_type.capitalized).fontWeight(.semibold)
                    Text(timeFormatter.string(from: log.timestamp))
                        .font(.subheadline).foregroundColor(.gray)
                }
                
                Spacer()

                Button(action: onEdit)  { Image(systemName: "pencil").foregroundColor(.blue) }
                Button(action: onDelete){ Image(systemName: "trash").foregroundColor(.red)  }
            }
            .padding()
            .background(color(for: log.event_type))
            .cornerRadius(12)
        }
    }

    // MARK: - Reminder Row
    struct ReminderRow: View {
        let occurrence: SupabaseManager.ReminderOccurrenceWithTitle
        let timeFormatter: DateFormatter
        var onToggle: () -> Void
        var onEdit: () -> Void
        var onDelete: () -> Void

        private var titleText: String {
            (occurrence.reminders?.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Reminder"
        }

        var body: some View {
            let isDone: Bool = (occurrence.status == "done")

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

                // Toggle complete
                Button(action: onToggle) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(isDone ? .green : .secondary)
                        .accessibilityLabel(isDone ? "Mark as pending" : "Mark as done")
                }

                // Edit / Delete
                Button(action: onEdit)  { Image(systemName: "pencil").foregroundColor(.blue) }
                Button(action: onDelete){ Image(systemName: "trash").foregroundColor(.red)  }
            }
            .padding()
            .background(Color.red.opacity(0.10)) // light red card
            .cornerRadius(12)
        }
    }


    
}
