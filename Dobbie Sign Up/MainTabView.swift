import SwiftUI

struct MainTabView: View {
    @Binding var isSignedIn: Bool

    // Dog profile info
    @State private var dogName: String = "your dog"
    @State private var dogBreed: String = ""
    @State private var dogGender: String = ""
    @State private var dogDob: Date = Date()
    @State private var dogWeight: String = ""

    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
  

    var body: some View {
        TabView {
            // ✅ HOME TAB
            NavigationStack {
                if let errorMessage = errorMessage {
                    VStack {
                        Text("⚠️ \(errorMessage)")
                            .foregroundColor(.red)
                        Button("Retry") {
                            Task { await loadFromSupabase() }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    HomeView(
                        isSignedIn: $isSignedIn,
                        dogName: dogName
                    )
                }
            }
            // Keep the Home data fresh, but DON'T create realtime here anymore
            .task {
                await InsightsData.shared.refreshFromSupabase()
            }
            .tabItem {
                Image(systemName: "house.fill")
                Text("Home")
            }

            // ✅ CALENDAR TAB
            NavigationStack { CalendarView() }
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Calendar")
                }

            
            // ✅ CHAT TAB
            NavigationStack {
                ChatView(
                    dogName: dogName,
                    dogBreed: dogBreed,
                    dogGender: dogGender,
                    dogDob: dogDob,
                    dogWeight: dogWeight
                )
            }
            .tabItem {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                Text("Chat")
            }
            
            // ✅ DASHBOARDS TAB
            NavigationStack {
                DoggieDashboardsView()   // ✅ no argument needed
            }
            .tabItem { Label("Dashboards", systemImage: "chart.bar.doc.horizontal") }

            SettingsView() // ⬅️ new
                            .tabItem { Label("Settings", systemImage: "gearshape") }


        }
        // Load dog/profile at app start
        .task { await loadFromSupabase() }

        // 🔗 ATTACH REALTIME (v2) ONCE FOR THE WHOLE APP
        // This keeps the channel alive across tabs.
        .task {
            await InsightsData.shared.attachRealtime()
        }
        // If you ever need to fully tear down realtime when leaving this view:
        // .onDisappear { Task { await InsightsData.shared.detachRealtime() } }

        .onReceive(SupabaseManager.shared.$lastError) { err in
            if let err = err { errorMessage = err }
        }
    }

    // MARK: - Supabase Fetch
    private func loadFromSupabase() async {
        do {
            guard let dogId = try await SupabaseManager.shared.getDogId() else {
                errorMessage = "No dog profile found"
                isLoading = false
                return
            }

            let dogs: [Dog] = try await SupabaseManager.shared.client
                .from("dogs")
                .select()
                .eq("id", value: dogId)
                .execute()
                .value

            if let firstDog = dogs.first {
                dogName = firstDog.name
                dogBreed = firstDog.breed
                dogGender = firstDog.gender

                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dogDob = dateFormatter.date(from: firstDog.dob) ?? Date()
                if let weightVal = firstDog.weight {
                    dogWeight = String(weightVal)
                }
            }

            isLoading = false
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

#Preview {
    MainTabView(isSignedIn: .constant(true))
}
