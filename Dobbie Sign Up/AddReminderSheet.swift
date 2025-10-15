import SwiftUI

struct AddReminderSheet: View {
    @Binding var isPresented: Bool
    var onSaved: () -> Void

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var schedule: Schedule = .once
    @State private var weekdayMask: Set<Int> = [] // Mon=0..Sun=6
    @State private var intervalDays: Int = 2
    @State private var dateOnce: Date = Date()
    @State private var startDate: Date = Date()
    @State private var endDate: Date? = nil
    @State private var times: [Date] = [Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: Date())!]

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
                        scheduleSpecificCard
                        timesCard
                        durationCard
                        footerButtons
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Sections

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.99, green: 0.98, blue: 0.95),
                     Color(red: 0.96, green: 0.92, blue: 0.86)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ).ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .font(.title3)
                    .foregroundStyle(.red.opacity(0.8))
                Text("Create Reminder")
                    .font(.title2).fontWeight(.semibold)
            }
            Text("You’ll get notified on the schedule you choose.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
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
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.secondary)
                    Text("When do you want to be reminded?")
                        .font(.headline)
                }

                Picker("", selection: $schedule) {
                    ForEach(Schedule.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var scheduleSpecificCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                switch schedule {
                case .once:
                    LabeledRow(systemImage: "calendar", label: "Date") {
                        DatePicker("", selection: $dateOnce, displayedComponents: .date)
                            .labelsHidden()
                    }

                case .weekly:
                    HStack(spacing: 8) {
                        Image(systemName: "repeat")
                            .foregroundStyle(.secondary)
                        Text("On These Days").font(.headline)
                    }
                    WeekdayChips(mask: $weekdayMask)

                case .interval:
                    LabeledRow(systemImage: "repeat", label: "Interval") {
                        Stepper("Every \(intervalDays) day(s)", value: $intervalDays, in: 1...30)
                            .labelsHidden()
                    }

                case .daily, .monthly:
                    // No additional controls beyond the picker; keep a light hint
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text(schedule == .daily ? "Every day at the times below." : "Same day each month.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        Spacer(minLength: 8)
                        Button {
                            times.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .accessibilityLabel("Remove time")
                    }
                }

                Button {
                    let base = times.last ?? Date()
                    let next = Calendar.current.date(byAdding: .hour, value: 1, to: base) ?? Date()
                    times.append(next)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add a time")
                    }
                }
            }
        }
    }

    private var durationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text("Duration").font(.headline)
                }

                LabeledRow(systemImage: "calendar", label: "Start Date") {
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden()
                }

                Toggle(isOn: Binding(get: { endDate != nil },
                                     set: { $0 ? (endDate = startDate) : (endDate = nil) })) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                        Text("End Date")
                    }
                }

                if endDate != nil {
                    LabeledRow(systemImage: "calendar", label: "End") {
                        DatePicker(
                            "",
                            selection: Binding<Date>(get: { endDate ?? startDate }, set: { endDate = $0 }),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }
                }
            }
        }
    }

    private var footerButtons: some View {
        VStack(spacing: 12) {
            Button(action: save) {
                Text("Add Reminder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(PrimaryRoundedButton())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.6)

            Button(role: .cancel) {
                isPresented = false
            } label: {
                Text("Cancel")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
    }

    // MARK: - Save (unchanged behavior)
    private func save() {
        Task {
            guard let dogId = try await SupabaseManager.shared.getDogId() else { return }

            let timeStrings = times.map { d -> String in
                let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = .current
                return f.string(from: d)
            }

            let maskInt: Int? = (schedule == .weekly) ? weekdayMask.reduce(0) { $0 | (1 << $1) } : nil

            let payload = SupabaseManager.NewReminder(
                title: title.trimmingCharacters(in: .whitespaces),
                notes: notes.isEmpty ? nil : notes,
                scheduleType: schedule.rawValue,
                weekdayMask: maskInt,
                intervalDays: (schedule == .interval) ? intervalDays : nil,
                dateOnce: (schedule == .once) ? dateOnce : nil,
                times: timeStrings,
                startDate: startDate,
                endDate: endDate,
                tz: TimeZone.current.identifier
            )

            do {
                _ = try await SupabaseManager.shared.createReminder(dogId: dogId, new: payload)
                await MainActor.run {
                    onSaved()
                    isPresented = false
                }
            } catch {
                print("❌ createReminder failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Styled weekday chips (Mon..Sun)
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
// MARK: - UI helpers (scoped to this file)

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
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(label)
                .font(.subheadline)
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
