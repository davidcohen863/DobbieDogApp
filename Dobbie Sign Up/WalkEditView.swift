import SwiftUI

struct WalkEditView: View {
    @Environment(\.dismiss) private var dismiss

    let dogId: String
    var existingLog: SupabaseManager.ActivityLog? = nil   // nil = create, non-nil = edit
    var onSaved: (() -> Void)? = nil
    var onDeleted: (() -> Void)? = nil

    // Manual fields
    @State private var start = Date().addingTimeInterval(-30 * 60)
    @State private var end = Date()
    @State private var distanceMeters: String = ""   // we can’t prefill until ActivityLog includes metadata
    @State private var notes: String = ""

    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var error: String?

    // MARK: - Init (prefill when editing)
    init(
        dogId: String,
        existingLog: SupabaseManager.ActivityLog? = nil,
        onSaved: (() -> Void)? = nil,
        onDeleted: (() -> Void)? = nil
    ) {
        self.dogId = dogId
        self.existingLog = existingLog
        self.onSaved = onSaved
        self.onDeleted = onDeleted

        // Prefill using what we have today:
        // - Use log.timestamp as END
        // - Assume ~30 min duration for START as a sensible default
        // - Prefill notes
        if let log = existingLog {
            _end = State(initialValue: log.timestamp)
            _start = State(initialValue: log.timestamp.addingTimeInterval(-30 * 60))
            _notes = State(initialValue: log.notes ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                ScrollView { content }
                if isSaving {
                    ProgressView("Saving...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
                if isDeleting {
                    ProgressView("Deleting…")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
            }
            .navigationTitle(existingLog == nil ? "Log Walk 🐾" : "Edit Walk 🐾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
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

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            timeCard
            detailsCard
            if let error {
                Text("⚠️ \(error)")
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            footerButtons
        }
        .padding(.top, 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "pawprint.fill")
                    .font(.title3)
                    .foregroundStyle(.brown.opacity(0.7))
                Text(existingLog == nil ? "Walk Details" : "Edit Walk")
                    .font(.title2).fontWeight(.semibold)
            }
            Text("Log Dobbie’s walk with start/end time and distance.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var timeCard: some View {
        Card {
            VStack(spacing: 14) {
                LabeledRow(systemImage: "clock.fill", label: "Start") {
                    DatePicker("", selection: $start, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }

                Divider().padding(.horizontal, -4)

                LabeledRow(systemImage: "clock", label: "End") {
                    DatePicker("", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }

                Divider().padding(.horizontal, -4)

                LabeledRow(systemImage: "hourglass", label: "Duration") {
                    Text(durationText).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var detailsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                LabeledRow(systemImage: "figure.walk", label: "Distance") {
                    HStack {
                        TextField("Meters", text: $distanceMeters)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 80)
                        Text("m").foregroundStyle(.secondary)
                    }
                }

                Divider().padding(.horizontal, -4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "note.text")
                            .foregroundStyle(.secondary)
                        Text("Notes").font(.headline)
                    }

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                            .fill(.clear)
                            .frame(minHeight: 120)

                        TextEditor(text: $notes)
                            .frame(minHeight: 120)
                            .padding(8)
                            .scrollContentBackground(.hidden)

                        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Add any helpful details…")
                                .foregroundStyle(.secondary)
                                .padding(.top, 14)
                                .padding(.leading, 14)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
    }

    private var footerButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task { await save() }
            } label: {
                Text(isSaving ? "Saving…" : (existingLog == nil ? "Save Walk" : "Save Changes"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(PrimaryRoundedButton())
            .disabled(isSaving || end <= start)

            if let log = existingLog {
                Button(role: .destructive) {
                    Task { await delete(log) }
                } label: {
                    Text("Delete Walk")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }

            Button(role: .cancel) {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
    }

    // MARK: - Logic

    private var durationText: String {
        let s = max(0, end.timeIntervalSince(start))
        let H = Int(s) / 3600
        let M = (Int(s) % 3600) / 60
        return H > 0 ? "\(H)h \(M)m" : "\(M)m"
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let duration = max(0, end.timeIntervalSince(start))
        let dist = Double(distanceMeters.replacingOccurrences(of: ",", with: "."))

        let meta = SupabaseManager.WalkMetadata(
            source: SupabaseManager.WalkSource.manual,
            start_time: start,
            end_time: end,
            duration_s: Int(duration.rounded()),
            distance_m: dist,
            calories_kcal: nil,
            health_workout_id: nil
        )

        do {
            if let log = existingLog {
                // ✏️ EDIT
                try await SupabaseManager.shared.updateWalkLog(
                    id: log.id,
                    metadata: meta,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
                )
            } else {
                // ➕ CREATE
                try await SupabaseManager.shared.insertWalkLog(
                    dogId: dogId,
                    metadata: meta,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
                )
            }
            onSaved?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            print("❌ Failed to save walk:", error.localizedDescription)
        }
    }

    private func delete(_ log: SupabaseManager.ActivityLog) async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        await SupabaseManager.shared.deleteLog(log)
        onDeleted?()
        dismiss()
    }
}

// MARK: - Local UI helpers (scoped to this file)

private struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
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
