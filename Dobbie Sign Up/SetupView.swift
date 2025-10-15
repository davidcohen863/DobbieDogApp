//
//  SetupWizardView.swift
//  Dobbie Sign Up
//

import SwiftUI
import UIKit
import Supabase

// MARK: - ViewModel
class SetupViewModel: ObservableObject {
    // Create Dog fields
    @Published var name: String = ""
    @Published var breed: String = ""
    @Published var dob: Date = Date()
    @Published var gender: String = ""
    @Published var weight: String = ""

    // Flow
    @Published var stepIndex: Int = 0

    // Join-by-code
    @Published var wantsToJoin: Bool = false
    @Published var joinCode: String = ""
    @Published var isWorking: Bool = false
    @Published var errorText: String?
}

struct SetupWizardView: View {
    @ObservedObject var vm: SetupViewModel
    @Binding var isSignedIn: Bool
    @Binding var isSetupComplete: Bool

    // 3 steps if creating a dog; 2 if just joining
    private var totalSteps: Int { vm.wantsToJoin ? 2 : 3 }

    var body: some View {
        VStack {
            TabView(selection: $vm.stepIndex) {

                // STEP 0: Choose create vs join
                VStack(spacing: 24) {
                    Text("Welcome to Dobbie 👋")
                        .font(.title2).fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    CardContainer {
                        VStack(alignment: .leading, spacing: 16) {
                            Toggle(isOn: $vm.wantsToJoin.animation()) {
                                Text("Join an existing family").font(.headline)
                            }
                            .padding(.bottom, 4)
                            .onChange(of: vm.wantsToJoin) { _, joining in
                                // Clear UI noise when switching modes
                                vm.errorText = nil
                                vm.isWorking = false
                                if joining { vm.stepIndex = 0 }
                            }

                            if vm.wantsToJoin {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Ask someone in the family for the **Share Code**.")
                                        .font(.subheadline)

                                    HStack(spacing: 12) {
                                        TextField("Enter code", text: $vm.joinCode)
                                            .keyboardType(.asciiCapable)
                                            .textInputAutocapitalization(.characters)
                                            .autocorrectionDisabled()
                                            .textContentType(.oneTimeCode)
                                            .font(.system(.body, design: .monospaced))
                                            .padding()
                                            .background(Color(.systemGray6))
                                            .cornerRadius(12)
                                            .disabled(vm.isWorking)
                                            .submitLabel(.go)
                                            .onSubmit { Task { await joinByCode() } }
                                            .task {
                                                // Optional: auto-fill if clipboard looks like a code
                                                if vm.joinCode.isEmpty,
                                                   let clip = UIPasteboard.general.string {
                                                    let s = clip
                                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                                        .uppercased()
                                                        .replacingOccurrences(of: "-", with: "")
                                                    if s.range(of: #"^[A-F0-9]{6,12}$"#, options: .regularExpression) != nil {
                                                        vm.joinCode = clip
                                                    }
                                                }
                                            }

                                        Button {
                                            Task { await joinByCode() }
                                        } label: {
                                            if vm.isWorking {
                                                ProgressView().controlSize(.small)
                                            } else {
                                                Text("Join").fontWeight(.semibold)
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(vm.joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isWorking)
                                    }

                                    if let err = vm.errorText {
                                        Text(err)
                                            .font(.footnote)
                                            .foregroundStyle(.red)
                                    }
                                }
                            } else {
                                Text("Or create your first dog to start tracking walks, sleep, and reminders.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    }
                }
                .tag(0)

                // STEP 1A: (if creating) Dog Info
                if !vm.wantsToJoin {
                    VStack(spacing: 24) {
                        Text("Tell us about your dog 🐶")
                            .font(.title2).fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)

                        CardContainer {
                            VStack(spacing: 16) {
                                CustomTextField("Name", text: $vm.name)
                                CustomTextField("Breed", text: $vm.breed)

                                DatePicker("Birthday", selection: $vm.dob, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)

                                Picker("Gender", selection: $vm.gender) {
                                    Text("Male").tag("Male")
                                    Text("Female").tag("Female")
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)

                                CustomTextField("Weight (kg)", text: $vm.weight, keyboardType: .decimalPad)
                            }
                            .padding()
                        }
                    }
                    .tag(1)
                }

                // LAST STEP: Done
                VStack(spacing: 24) {
                    Text("Setup Complete 🎉")
                        .font(.largeTitle).fontWeight(.bold)

                    Button("Finish") {
                        if vm.wantsToJoin {
                            // Joined an existing family → if a dog exists, we already marked complete.
                            isSetupComplete = true
                        } else {
                            saveDog()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .tag(totalSteps - 1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Navigation Bar (Back / Next)
            HStack {
                if vm.stepIndex > 0 {
                    Button("Back") { vm.stepIndex -= 1 }
                }
                Spacer()
                if vm.stepIndex < totalSteps - 1 {
                    Button("Next") { vm.stepIndex += 1 }
                        .disabled(vm.wantsToJoin && vm.stepIndex == 0) // joining uses "Join" button
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))

        // ✅ If a dog becomes available (posted right after join), finish setup automatically.
        .onReceive(NotificationCenter.default.publisher(for: .activeDogBecameAvailable)) { _ in
            Task { @MainActor in
                isSetupComplete = true
            }
        }

        // ✅ On appear, if a dog is already cached (e.g., returning user who is now a member), complete setup.
        .task {
            if let _ = try? await SupabaseManager.shared.getDogId(forceRefresh: true) {
                await MainActor.run { isSetupComplete = true }
            }
        }
    }

    // MARK: - Join by share code
    private func joinByCode() async {
        await MainActor.run { vm.isWorking = true; vm.errorText = nil }

        let code = vm.joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            await MainActor.run {
                vm.isWorking = false
                vm.errorText = "Please enter a code."
            }
            return
        }

        do {
            let familyId = try await SupabaseManager.shared.acceptFamilyShareCode(code)
            print("✅ Joined family:", familyId)

            // Try to fetch a dog immediately after join
            if let _ = try? await SupabaseManager.shared.getDogId(forceRefresh: true) {
                // Dog exists → finish setup now
                await MainActor.run {
                    vm.isWorking = false
                    isSetupComplete = true
                }
            } else {
                // No dog yet (edge case) → advance to Done; Finish button will close.
                await MainActor.run {
                    vm.isWorking = false
                    vm.stepIndex = 1   // 0 (choose/join) → 1 (done)
                }
            }
        } catch {
            await MainActor.run {
                vm.isWorking = false
                vm.errorText = error.localizedDescription
            }
        }
    }

    // MARK: - Save Dog (create flow)
    private func saveDog() {
        Task {
            do {
                let session = try await SupabaseManager.shared.client.auth.session
                let user = session.user

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let weightValue: Double? = vm.weight.isEmpty ? nil : Double(vm.weight)

                struct DogInsert: Encodable {
                    let name: String
                    let breed: String
                    let dob: String?
                    let gender: String?
                    let weight: Double?
                }

                let insertDog = DogInsert(
                    name: vm.name,
                    breed: vm.breed,
                    dob: dateFormatter.string(from: vm.dob),
                    gender: vm.gender,
                    weight: weightValue
                )

                let newDog: SupabaseManager.DogLite = try await SupabaseManager.shared.client
                    .from("dogs")
                    .insert(insertDog)
                    .select("id,name")
                    .single()
                    .execute()
                    .value

                print("✅ Saved dog: \(newDog.id) for user \(user.id.uuidString)")
                SupabaseManager.shared.cacheDogId(newDog.id)

                await MainActor.run { isSetupComplete = true }
            } catch {
                print("❌ Error saving dog:", error.localizedDescription)
            }
        }
    }
}

// MARK: - Shared UI
struct CardContainer<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack { content }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            .padding(.horizontal)
    }
}

struct CustomTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    init(_ placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) {
        self.placeholder = placeholder
        self._text = text
        self.keyboardType = keyboardType
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }
}
