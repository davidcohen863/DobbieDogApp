import SwiftUI
import UIKit // for UIPasteboard

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct SettingsView: View {
    // Families
    @State private var families: [SupabaseManager.Family] = []
    @State private var selectedFamilyId: String?

    // Invites (link-based + codes)
    @State private var pending: [SupabaseManager.FamilyInvite] = []
    @State private var shareURL: URL?

    // Share code UI state
    @State private var showCodeSheet = false
    @State private var shareCode: String = ""
    @State private var shareCodeExpiresAt: String = ""  // ISO from server

    // UX
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                // MARK: Family
                Section("Family") {
                    if families.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No families yet").foregroundStyle(.secondary)
                            Button {
                                Task { await createFamily() }
                            } label: {
                                Label("Create new family", systemImage: "person.3")
                            }
                        }
                    } else {
                        Picker("Active Family", selection: $selectedFamilyId) {
                            ForEach(families, id: \.id) { fam in
                                Text(fam.name).tag(fam.id as String?)
                            }
                        }
                        .task(id: selectedFamilyId) {
                            await setActiveFamilyAndReload()
                        }
                    }
                }

                // MARK: Collaborators
                Section("Collaborators") {
                    // A) Invite link (kept)
                    Button {
                        Task { await createAndShareInvite() }
                    } label: {
                        Label("Invite via link", systemImage: "link.badge.plus")
                    }
                    .disabled(selectedFamilyId == nil)

                    // B) Generate a short share code (no Universal Link needed)
                    Button {
                        Task { await generateShareCode() }
                    } label: {
                        Label("Generate share code", systemImage: "number.circle")
                    }
                    .disabled(selectedFamilyId == nil)

                    if pending.isEmpty {
                        Text("No pending invites").foregroundStyle(.secondary)
                    } else {
                        ForEach(pending, id: \.id) { inv in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    // Show email OR “Invite”
                                    Text(inv.invited_email?.isEmpty == false ? (inv.invited_email ?? "") : "Invite")
                                        .font(.body)

                                    // Show share code chip if present
                                    if let code = inv.share_code, !code.isEmpty {
                                        HStack(spacing: 8) {
                                            Text(code)
                                                .font(.system(.body, design: .monospaced))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color(.systemGray6))
                                                .clipShape(Capsule())

                                            Button {
                                                UIPasteboard.general.string = code
                                                haptic(.success)
                                            } label: {
                                                Label("Copy code", systemImage: "doc.on.doc")
                                                    .labelStyle(.iconOnly)
                                            }
                                            .buttonStyle(.borderless)
                                            .foregroundStyle(.secondary)
                                        }
                                    }

                                    Text("Expires: \(pretty(inv.expires_at))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                // Row actions
                                Menu {
                                    // Copy link (optional)
                                    if let url = inviteURL(from: inv.token) {
                                        Button("Copy link") {
                                            UIPasteboard.general.url = url
                                            haptic(.success)
                                        }
                                    }
                                    // Copy code (quick access)
                                    if let code = inv.share_code, !code.isEmpty {
                                        Button("Copy code") {
                                            UIPasteboard.general.string = code
                                            haptic(.success)
                                        }
                                    }
                                    Button("Revoke", role: .destructive) {
                                        Task { await revoke(inv.id) }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                            }
                        }
                    }
                }

                // MARK: About
                Section("About") {
                    Text("Dobbie Tracker").bold()
                    Text("Invite family members to log and view your dog’s activity. Everyone in a family has the same access.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .overlay { if isLoading { ProgressView().controlSize(.large) } }
            .task { await initialLoad() }

            // Link share sheet (unchanged)
            .sheet(item: $shareURL) { url in
                ShareLink(item: url, message: Text("Join my family on Dobbie 🐶"))
            }

            // Share Code sheet
            .sheet(isPresented: $showCodeSheet) {
                ShareCodeSheet(
                    code: shareCode,
                    expiresText: pretty(shareCodeExpiresAt),
                    onCopy: {
                        UIPasteboard.general.string = shareCode
                        haptic(.success)
                    }
                )
                .presentationDetents([.medium])
            }

            .alert("Error", isPresented: .constant(error != nil), actions: {
                Button("OK") { error = nil }
            }, message: { Text(error ?? "") })
        }
    }

    // MARK: - Initial load
    private func initialLoad() async {
        isLoading = true
        defer { isLoading = false }
        do {
            families = try await SupabaseManager.shared.myFamilies()
            if selectedFamilyId == nil {
                selectedFamilyId = SupabaseManager.shared.getActiveFamilyId() ?? families.first?.id
            }
            await setActiveFamilyAndReload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Helpers
    @MainActor
    private func setActiveFamilyAndReload() async {
        guard let fid = selectedFamilyId else { pending = []; return }
        SupabaseManager.shared.setActiveFamilyId(fid)
        await loadPending()
    }

    private func loadPending() async {
        guard let fid = selectedFamilyId else { pending = []; return }
        do {
            pending = try await SupabaseManager.shared.pendingFamilyInvites(familyId: fid)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func createFamily() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fam = try await SupabaseManager.shared.createFamily(name: "My Family")
            families = try await SupabaseManager.shared.myFamilies()
            selectedFamilyId = fam.id
            await setActiveFamilyAndReload()
            haptic(.success)
        } catch {
            self.error = error.localizedDescription
            haptic(.error)
        }
    }

    private func createAndShareInvite() async {
        guard let fid = selectedFamilyId else { return }
        do {
            let url = try await SupabaseManager.shared.createFamilyInviteURL(familyId: fid)
            self.shareURL = url
            await loadPending()
            haptic(.success)
        } catch {
            self.error = error.localizedDescription
            haptic(.error)
        }
    }

    // Generate share code & show sheet
    // Share sheet trigger — guard against empty code
    private func generateShareCode() async {
        guard let fid = selectedFamilyId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await SupabaseManager.shared.createFamilyShareCode(familyId: fid)
            self.shareCode = res.code.uppercased()       // ← use tuple label `code`
            self.shareCodeExpiresAt = res.expiresAt      // ← use tuple label `expiresAt`
            self.showCodeSheet = true
            await loadPending()
            haptic(.success)
        } catch {
            self.error = error.localizedDescription
            haptic(.error)
        }
    }



    private func revoke(_ inviteId: String) async {
        do {
            try await SupabaseManager.shared.revokeFamilyInvite(inviteId: inviteId)
            await loadPending()
            haptic(.success)
        } catch {
            self.error = error.localizedDescription
            haptic(.error)
        }
    }

    private func inviteURL(from token: String) -> URL? {
        var comps = URLComponents(string: "https://dobbie.app/join")
        comps?.queryItems = [URLQueryItem(name: "token", value: token)]
        return comps?.url
    }

    private func pretty(_ isoString: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: isoString) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: d)
        }
        return isoString
    }
}

// MARK: - Share Code sheet
private struct ShareCodeSheet: View {
    let code: String
    let expiresText: String
    let onCopy: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Share Code")
                    .font(.headline)

                Text(code)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .padding(.vertical, 8)

                Text("Expires: \(expiresText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    ShareLink(item: code) {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)

                Spacer()
            }
            .padding()
            .navigationTitle("Invite")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
