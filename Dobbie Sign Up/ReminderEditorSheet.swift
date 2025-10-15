import SwiftUI


struct ReminderEditorSheet: View {
    enum Mode: Equatable { case create, edit(reminderId: UUID) }

    let mode: Mode
    @Binding var isPresented: Bool
    var onSaved: () -> Void

    // form state
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var schedule: Schedule = .once
    @State private var weekdayMaskSet: Set<Int> = []   // Mon=0..Sun=6
    @State private var intervalDays: Int = 2
    @State private var dateOnce: Date = Date()
    @State private var startDate: Date = Date()
    @State private var endDate: Date? = nil
    @State private var times: [Date] = [Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: Date())!]
    @State private var notificationsOn: Bool = true
    @State private var showNotifDeniedAlert = false
    @State private var isLoading = false
    @State private var isSaving = false

    enum Schedule: String, CaseIterable { case once, daily, weekly, interval, monthly }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !times.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        titleNotesCard
                        scheduleCard
                        notificationsCard
                        scheduleSpecificCard
                        timesCard
                        durationCard
                        footerButtons
                    }
                    
                    .alert("Notifications are disabled",
                           isPresented: $showNotifDeniedAlert,
                           actions: { Button("OK", role: .cancel) {} },
                           message: { Text("Enable notifications in Settings to receive reminders.") })
                    
                    .padding(.top, 8)
                }

                if isLoading || isSaving {
                    ProgressView(isLoading ? "Loading…" : "Saving…")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
            }
            .navigationTitle(modeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(primaryButtonTitle) { Task { await save() } }
                        .disabled(!canSave || isLoading || isSaving)
                }
            }
            .task { await loadIfEditing() }
        }
    }

    // MARK: - Appear / load existing reminder in edit mode
    private func loadIfEditing() async {
        guard case let .edit(reminderId) = mode else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await SupabaseManager.shared.client
                .from("reminders")
                .select("*")
                .eq("id", value: reminderId)
                .single()
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .deferredToDate
            let r = try decoder.decode(SupabaseManager.Reminder.self, from: response.data)
            notificationsOn = r.notifications_enabled ?? true

            
            // Populate form
            title = r.title
            notes = r.notes ?? ""
            schedule = Schedule(rawValue: r.schedule_type) ?? .once
            if let mask = r.weekday_mask { weekdayMaskSet = maskToSet(mask) }
            intervalDays = r.interval_days ?? 2

            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = .current
            startDate = df.date(from: r.start_date) ?? Date()
            endDate = r.end_date.flatMap { df.date(from: $0) }

            // times are ["HH:mm"]
            let timeDF = DateFormatter(); timeDF.dateFormat = "HH:mm"; timeDF.timeZone = .current
            times = r.times.compactMap { t in
                guard let hm = timeDF.date(from: t) else { return nil }
                let comps = Calendar.current.dateComponents([.hour, .minute], from: hm)
                return Calendar.current.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: Date())
            }
            if times.isEmpty { times = [Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: Date())!] }

            if schedule == .once, let d = r.date_once {
                dateOnce = df.date(from: d) ?? Date()
            }
        } catch {
            print("❌ load reminder failed:", error.localizedDescription)
        }
    }

    // MARK: - Save
    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            guard let dogId = try await SupabaseManager.shared.getDogId() else { return }

            // HH:mm strings
            let hhmm: [String] = times.map { d in
                let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = .current
                return f.string(from: d)
            }

            let maskInt: Int? = (schedule == .weekly) ? setToMask(weekdayMaskSet) : nil

            switch mode {
            case .create:
                var payload = SupabaseManager.NewReminder(
                    title: title.trimmingCharacters(in: .whitespaces),
                    notes: notes.isEmpty ? nil : notes,
                    scheduleType: schedule.rawValue,
                    weekdayMask: maskInt,
                    intervalDays: (schedule == .interval) ? intervalDays : nil,
                    dateOnce: (schedule == .once) ? dateOnce : nil,
                    times: hhmm,
                    startDate: startDate,
                    endDate: endDate,
                    tz: TimeZone.current.identifier
                )
                // ✅ persist the toggle at creation
                payload.notificationsEnabled = notificationsOn

                // ✅ capture the created reminder (we need its id)
                let created = try await SupabaseManager.shared.createReminder(dogId: dogId, new: payload)

                // ✅ ask for permission if needed and schedule local notifs
                if notificationsOn {
                    let ok = await NotificationManager.shared.requestAuthIfNeeded {
                        Task { @MainActor in showNotifDeniedAlert = true }
                    }
                    if ok {
                        await SupabaseManager.shared.rescheduleReminderLocalNotifications(reminderId: created.id,
                                                                                         titleOverride: title,
                                                                                         notesOverride: notes.isEmpty ? nil : notes)
                    }
                } else {
                    // make sure nothing is pending for this reminder (paranoia)
                    await NotificationManager.shared.cancelAll(for: created.id)
                }

                // 🔔 Notify UI + close
                await MainActor.run {
                    NotificationCenter.default.post(name: .remindersDidChange, object: nil)
                    onSaved()
                    isPresented = false
                }


            case let .edit(reminderId):
                struct UpdatePayload: Encodable {
                    let title: String
                    let notes: String?
                    let schedule_type: String
                    let weekday_mask: Int?
                    let interval_days: Int?
                    let date_once: String?
                    let times: [String]
                    let start_date: String
                    let end_date: String?
                    let tz: String
                }
                let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = .current

                let update = UpdatePayload(
                    title: title.trimmingCharacters(in: .whitespaces),
                    notes: notes.isEmpty ? nil : notes,
                    schedule_type: schedule.rawValue,
                    weekday_mask: maskInt,
                    interval_days: (schedule == .interval) ? intervalDays : nil,
                    date_once: (schedule == .once) ? df.string(from: dateOnce) : nil,
                    times: hhmm,
                    start_date: df.string(from: startDate),
                    end_date: endDate.map { df.string(from: $0) },
                    tz: TimeZone.current.identifier
                )

                try await SupabaseManager.shared.client
                    .from("reminders")
                    .update(update)
                    .eq("id", value: reminderId)
                    .execute()

                // ✅ Re-expand future occurrences so calendar dots reflect changes immediately
                // (Assumes you added SupabaseManager.reexpandReminderOccurrences)
                let cal = Calendar.current
                let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
                let anchor = cal.date(byAdding: .day, value: -7, to: startOfThisMonth)!  // backfill a week before the month
                try? await SupabaseManager.shared.reexpandReminderOccurrences(
                    reminderId: reminderId,
                    startFrom: anchor,
                    horizonDays: 120
                )
                
                // ✅ Persist toggle + reconcile local notifications
                await SupabaseManager.shared.setReminderNotifications(
                    reminderId: reminderId,
                    enabled: notificationsOn,
                    title: title,
                    notes: notes.isEmpty ? nil : notes
                )


                // 🔔 Notify calendar to refresh
                await MainActor.run {
                    NotificationCenter.default.post(name: .remindersDidChange, object: nil)
                    onSaved()
                    isPresented = false
                }
            }

        } catch {
            print("❌ save (create/edit) reminder failed:", error.localizedDescription)
        }
    }

    // MARK: - UI (same visuals as your AddReminderSheet)
    private var modeTitle: String { mode == .create ? "New Reminder" : "Edit Reminder" }
    private var primaryButtonTitle: String { mode == .create ? "Add" : "Save" }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.99, green: 0.98, blue: 0.95),
                     Color(red: 0.96, green: 0.92, blue: 0.86)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ).ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .font(.title3)
                    .foregroundStyle(.red.opacity(0.8))
                Text(mode == .create ? "Create Reminder" : "Edit Reminder")
                    .font(.title2).fontWeight(.semibold)
            }
            Text("You’ll get notified on the schedule you choose.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal).padding(.top, 8)
    }

    private var titleNotesCard: some View {
        Card {
            VStack(spacing: 14) {
                LabeledRow(systemImage: "text.cursor", label: "Title") {
                    TextField("What should we remind you?", text: $title)
                        .textInputAutocapitalization(.sentences)
                }
                Divider().padding(.horizontal, -4)
                LabeledRow(systemImage: "note.text", label: "Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
        }
    }

    private var scheduleCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(.secondary)
                    Text("When do you want to be reminded?").font(.headline)
                }
                Picker("", selection: $schedule) {
                    ForEach(Schedule.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }
    
    private var notificationsCard: some View {
        Card {
            LabeledRow(systemImage: "bell.fill", label: "Notifications") {
                Toggle("", isOn: $notificationsOn)
                    .labelsHidden()
                    .onChange(of: notificationsOn) { on, _ in
                        if on {
                            Task {
                                let ok = await NotificationManager.shared.requestAuthIfNeeded {
                                    Task { @MainActor in showNotifDeniedAlert = true }
                                }
                                if !ok {
                                    await MainActor.run { notificationsOn = false }
                                }

                            }
                        } else {
                            // no-op here; we cancel on save if turned off
                        }
                    }
            }
            Text("Turn this on to get local alerts at the scheduled times.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }


    private var scheduleSpecificCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                switch schedule {
                case .once:
                    LabeledRow(systemImage: "calendar", label: "Date") {
                        DatePicker("", selection: $dateOnce, displayedComponents: .date).labelsHidden()
                    }
                case .weekly:
                    HStack(spacing: 8) {
                        Image(systemName: "repeat").foregroundStyle(.secondary)
                        Text("On These Days").font(.headline)
                    }
                    WeekdayChips(mask: $weekdayMaskSet)
                case .interval:
                    LabeledRow(systemImage: "repeat", label: "Interval") {
                        Stepper("Every \(intervalDays) day(s)", value: $intervalDays, in: 1...30).labelsHidden()
                    }
                case .daily, .monthly:
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text(schedule == .daily ? "Every day at the times below." : "Same day each month.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var timesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill").foregroundStyle(.secondary)
                    Text("At what time?").font(.headline)
                }
                ForEach(Array(times.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        DatePicker("", selection: $times[index], displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact).labelsHidden()
                        Spacer(minLength: 8)
                        Button {
                            times.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .accessibilityLabel("Remove time")
                    }
                }
                Button {
                    let base = times.last ?? Date()
                    let next = Calendar.current.date(byAdding: .hour, value: 1, to: base) ?? Date()
                    times.append(next)
                } label: {
                    HStack { Image(systemName: "plus.circle.fill"); Text("Add a time") }
                }
            }
        }
    }

    private var durationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                    Text("Duration").font(.headline)
                }
                LabeledRow(systemImage: "calendar", label: "Start Date") {
                    DatePicker("", selection: $startDate, displayedComponents: .date).labelsHidden()
                }
                Toggle(isOn: Binding(get: { endDate != nil },
                                     set: { $0 ? (endDate = startDate) : (endDate = nil) })) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(.secondary)
                        Text("End Date")
                    }
                }
                if endDate != nil {
                    LabeledRow(systemImage: "calendar", label: "End") {
                        DatePicker("", selection: Binding<Date>(get: { endDate ?? startDate }, set: { endDate = $0 }),
                                   displayedComponents: .date).labelsHidden()
                    }
                }
            }
        }
    }

    private var footerButtons: some View {
        VStack(spacing: 12) {
            Button { Task { await save() } } label: {
                Text(mode == .create ? "Add Reminder" : "Save Changes")
                    .font(.headline)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(PrimaryRoundedButton())
            .disabled(!canSave || isLoading || isSaving)
            .opacity(canSave ? 1 : 0.6)

            Button(role: .cancel) { isPresented = false } label: {
                Text("Cancel").font(.subheadline).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal).padding(.bottom, 24)
    }

    // MARK: - Helpers
    private func setToMask(_ set: Set<Int>) -> Int { set.reduce(0) { $0 | (1 << $1) } }
    private func maskToSet(_ mask: Int) -> Set<Int> {
        var s = Set<Int>(); for i in 0..<7 { if (mask & (1 << i)) != 0 { s.insert(i) } }; return s
    }
}

// ==== Reused small UI bits (copied from your AddReminderSheet) ====

private struct WeekdayChips: View {
    @Binding var mask: Set<Int>   // Mon=0..Sun=6
    private let labels = ["M","T","W","T","F","S","S"]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<7, id: \.self) { i in
                let selected = mask.contains(i)
                Text(labels[i])
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selected ? Color.accentColor : Color.secondary.opacity(0.15))
                    )
                    .foregroundStyle(selected ? .white : .primary)
                    .onTapGesture { if selected { mask.remove(i) } else { mask.insert(i) } }
                    .animation(.spring(response: 0.2, dampingFraction: 0.85), value: selected)
            }
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.background.opacity(0.6))
                    .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal)
    }
}

private struct LabeledRow<RightContent: View>: View {
    let systemImage: String
    let label: String
    @ViewBuilder var rightContent: () -> RightContent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 22)
            Text(label).font(.subheadline)
            Spacer(minLength: 12)
            rightContent()
        }
        .padding(.vertical, 6)
    }
}

private struct PrimaryRoundedButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1.0))
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let remindersDidChange = Notification.Name("remindersDidChange")
}
