import SwiftUI
import Supabase

struct EditActivityView: View {
    let log: SupabaseManager.ActivityLog

    @Binding var isPresented: Bool
    var onSave: (SupabaseManager.ActivityLog) -> Void
    var onDelete: (SupabaseManager.ActivityLog) -> Void

    @State private var editedTimestamp: Date
    @State private var editedType: String
    @State private var editedNotes: String
    @State private var isUploading = false
    @State private var isSaving = false

    // 👉 New: a URL we actually render (with a cache-busting query)
    @State private var displayURL: URL? = nil

    private let types = ["pee", "poo", "eat", "walk", "play", "sleep", "drink", "zoomies"]

    init(
        log: SupabaseManager.ActivityLog,
        isPresented: Binding<Bool>,
        onSave: @escaping (SupabaseManager.ActivityLog) -> Void,
        onDelete: @escaping (SupabaseManager.ActivityLog) -> Void
    ) {
        self.log = log
        self._isPresented = isPresented
        self.onSave = onSave
        self.onDelete = onDelete

        _editedTimestamp = State(initialValue: log.timestamp)
        _editedType = State(initialValue: log.event_type)
        _editedNotes = State(initialValue: log.notes ?? "")
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
            }
            .navigationTitle("Edit Activity 🐾")
            .navigationBarTitleDisplayMode(.inline)
        }
    }




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
            dateAndTypeCard
            notesCard
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
                Text("Edit Activity")
                    .font(.title2).fontWeight(.semibold)
            }
            Text("Update your pup’s activity log below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var dateAndTypeCard: some View {
        Card {
            VStack(spacing: 14) {
                LabeledRow(systemImage: "clock.fill", label: "Date & Time") {
                    DatePicker("", selection: $editedTimestamp, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }

                Divider().padding(.horizontal, -4)

                LabeledRow(systemImage: "tag.fill", label: "Activity") {
                    Picker("", selection: $editedType) {
                        ForEach(types, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(MenuPickerStyle())
                }
            }
        }
    }

    private var notesCard: some View {
        Card {
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

                    TextEditor(text: $editedNotes)
                        .frame(minHeight: 120)
                        .padding(8)
                        .scrollContentBackground(.hidden)

                    if editedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

    private var footerButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    isSaving = true
                    defer { isSaving = false }

                    let updated = SupabaseManager.ActivityLog(
                        id: log.id,
                        dog_id: log.dog_id,
                        event_type: editedType,
                        timestamp: editedTimestamp,
                        notes: editedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editedNotes,
                       
                    )

                    await SupabaseManager.shared.updateLog(updated)
                    await InsightsData.shared.refreshFromSupabase()
                    onSave(updated)
                    isPresented = false
                }
            } label: {
                Text("Save Changes")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(PrimaryRoundedButton())

            Button(role: .destructive) {
                onDelete(log)
                isPresented = false
            } label: {
                Text("Delete Activity")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

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


}

// MARK: - UI helpers

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
