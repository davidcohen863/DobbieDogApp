import SwiftUI

// MARK: - Date Utilities
enum DateUtils {
    static let posix = Locale(identifier: "en_US_POSIX")

    static let isoParserUTC = isoPrinterUTC // same options; use printer as parser

    static let displayDateTime: DateFormatter = {
        let df = DateFormatter()
        df.locale = posix
        df.calendar = Calendar(identifier: .gregorian)
        df.timeZone = .autoupdatingCurrent
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    static let displayDate: DateFormatter = {
        let df = DateFormatter()
        df.locale = posix
        df.calendar = Calendar(identifier: .gregorian)
        df.timeZone = .autoupdatingCurrent
        df.dateFormat = "d MMMM yyyy"
        return df
    }()

    static let displayTime: DateFormatter = {
        let df = DateFormatter()
        df.locale = posix
        df.calendar = Calendar(identifier: .gregorian)
        df.timeZone = .autoupdatingCurrent
        df.dateFormat = "HH:mm"
        return df
    }()

    // ISO8601 with fractional seconds
    static let isoParserUTC_frac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    // ISO8601 without fractional seconds (fallback)
    static let isoParserUTC_nofrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    static let isoPrinterUTC: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    /// Parse either fractional or non-fractional ISO8601Z
    static func parseISOZ(_ s: String) -> Date? {
        if let d = isoParserUTC_frac.date(from: s) { return d }
        return isoParserUTC_nofrac.date(from: s)
    }

    static func nowContext() -> (isoZ: String, localLong: String, tzID: String, tzOffset: String) {
        let now = Date()
        let isoZ = isoPrinterUTC.string(from: now)
        let localLong = "\(displayDate.string(from: now)) \(displayTime.string(from: now))"
        let tz = TimeZone.autoupdatingCurrent
        let seconds = tz.secondsFromGMT(for: now)
        let hours = seconds / 3600
        let mins = abs((seconds % 3600) / 60)
        let sign = hours >= 0 ? "+" : "-"
        let tzOffset = String(format: "GMT%@%02d:%02d", sign, abs(hours), mins)
        return (isoZ, localLong, tz.identifier, tzOffset)
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let isUser: Bool
    let text: String
    
    init(id: UUID = UUID(), isUser: Bool, text: String) {
        self.id = id
        self.isUser = isUser
        self.text = text
    }
}

struct ChatView: View {
    var dogName: String
    var dogBreed: String
    var dogGender: String
    var dogDob: Date
    var dogWeight: String
    
    @Environment(\.scenePhase) private var scenePhase
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading = false
    
    private let initialGreeting = ChatMessage(isUser: false, text: "Hi, I’m Dobbie AI 🐾 — your dog’s assistant.")
    
    let suggestedPrompts = [
        "Summarize today’s activities",
        "Spot unusual patterns",
        "Any health concerns?",
        "How old is my dog?",
        "When is the next vet appointment?"
    ]
    
    private let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { msg in
                        HStack {
                            if msg.isUser {
                                Spacer()
                                Text(msg.text)
                                    .padding()
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(12)
                                    .frame(maxWidth: 250, alignment: .trailing)
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(msg.text)
                                        .padding()
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(12)
                                        .frame(maxWidth: 250, alignment: .leading)
                                    
                                    Text("AI-generated")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .padding()
            }
            
            if isLoading {
                ProgressView("Thinking...")
                    .padding()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(suggestedPrompts, id: \.self) { prompt in
                        Button(prompt) {
                            sendMessage(prompt)
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
            }
            
            HStack {
                TextField("Ask anything about your dog…", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Send") {
                    sendMessage(inputText)
                }
                .disabled(inputText.isEmpty)
            }
            .padding()
        }
        .navigationTitle("Chat")
               .task {
                   await loadChatFromSupabase()
                   if messages.isEmpty {
                       messages = [initialGreeting]
                   }
               }
               .onChange(of: scenePhase) { _, newPhase in
                   Task { @MainActor in
                       switch newPhase {
                       case .background:
                           // User "closed" the app → clear persisted chat and reset local session
                           await clearChatOnSupabase()
                           messages = [initialGreeting]
                       default:
                           break
                       }
                   }
               }
           }

           // MARK: - Messaging
           private func sendMessage(_ text: String) {
               guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
               messages.append(ChatMessage(isUser: true, text: text))
               inputText = ""

               Task {
                   isLoading = true
                   let reply = await generateAIResponse(for: text)
                   messages.append(ChatMessage(isUser: false, text: reply))
                   isLoading = false

                   // (Optional) Cap history so UI stays snappy even if user never closes
                   if messages.count > 50 {
                       messages = Array(messages.suffix(50))
                   }

                   await saveChatToSupabase()
               }
           }
    
    // MARK: - Save Chat
    func saveChatToSupabase() async {
            do {
                guard let dogId = try await SupabaseManager.shared.getDogId() else { return }
                struct ChatInsert: Codable { var dog_id: String; var messages: [ChatMessage] }
                let insert = ChatInsert(dog_id: dogId, messages: messages)

                try await SupabaseManager.shared.client
                    .from("chats")
                    .upsert(insert, onConflict: "dog_id")
                    .execute()

                print("✅ Chat saved to Supabase")
            } catch {
                print("❌ Failed to save chat: \(error.localizedDescription)")
            }
        }
    
    // MARK: - Load Chat
    func loadChatFromSupabase() async {
            do {
                guard let dogId = try await SupabaseManager.shared.getDogId() else { return }

                let chats: [ChatRecord] = try await SupabaseManager.shared.client
                    .from("chats")
                    .select()
                    .eq("dog_id", value: dogId)
                    .order("created_at", ascending: false)
                    .limit(1)
                    .execute()
                    .value

                if let latest = chats.first {
                    messages = latest.messages
                }
            } catch {
                print("❌ Failed to load chat: \(error.localizedDescription)")
            }
        }

        struct ChatRecord: Codable {
            let id: UUID
            let dog_id: String
            let messages: [ChatMessage]
            let created_at: String
        }

    // MARK: - Clear Chat (called on app close/background)
       private func clearChatOnSupabase() async {
           do {
               guard let dogId = try await SupabaseManager.shared.getDogId() else { return }
               struct ChatInsert: Codable { var dog_id: String; var messages: [ChatMessage] }
               // Persist an empty conversation so the next launch starts fresh
               let insert = ChatInsert(dog_id: dogId, messages: [])

               try await SupabaseManager.shared.client
                   .from("chats")
                   .upsert(insert, onConflict: "dog_id")
                   .execute()

               print("🧹 Cleared chat on Supabase")
           } catch {
               print("❌ Failed to clear chat: \(error.localizedDescription)")
           }
       }
    
    // MARK: - OpenAI Integration (+ Reminders added to context)
    // Replace your entire generateAIResponse(...) with this:

    private func generateAIResponse(for query: String) async -> String {
        do {
            guard let dogId = try await SupabaseManager.shared.getDogId() else {
                return "No dog ID found."
            }

            // Build the Edge Function URL: https://<ref>.functions.supabase.co/chat-orchestrator
            let url = SupabaseManager.shared.functionsBaseURL.appendingPathComponent("chat-orchestrator")

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")

            // Forward the user JWT (recommended)
            // Forward the user JWT (recommended)
            if let session = try? await SupabaseManager.shared.client.auth.session {
                let access = session.accessToken
                req.addValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
            }


            struct Payload: Encodable { let query: String; let dog_id: String }
            req.httpBody = try JSONEncoder().encode(Payload(query: query, dog_id: dogId))

            let (data, _) = try await URLSession.shared.data(for: req)

            struct Resp: Decodable { let answer: String?; let error: String? }
            let dec = try JSONDecoder().decode(Resp.self, from: data)
            if let err = dec.error { return "❌ \(err)" }
            return dec.answer ?? "⚠️ No response"
        } catch {
            return "❌ API error: \(error.localizedDescription)"
        }
    }

}

