import SwiftUI
import AuthenticationServices
import Supabase

struct SignUpView: View {
    @Binding var isSignedIn: Bool

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoginMode = false   // toggle between SignUp & Login

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.mint, Color.purple.opacity(0.7), Color.pink.opacity(0.7)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)

            VStack(spacing: 30) {
                Text("Keeping dogs and owners happy")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)

                Spacer(minLength: 200)

                // MARK: - Sign in with Apple
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                    // (Optional) You can add a nonce if you want extra protection
                } onCompletion: { result in
                    switch result {
                    case .success(let authResults):
                        handleAppleSignIn(authResults)
                    case .failure(let error):
                        Task { @MainActor in
                            errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
                        }
                        print("❌ Apple Sign-In failed: \(error.localizedDescription)")
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .cornerRadius(10)
                .padding(.horizontal, 40)

                // MARK: - Email Auth
                VStack(spacing: 10) {
                    TextField("Email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.emailAddress)
                        .padding(.horizontal, 40)

                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal, 40)

                    if isLoginMode {
                        Button("Log In") {
                            Task { await emailLogIn() }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal, 40)
                    } else {
                        Button("Sign Up") {
                            Task { await emailSignUp() }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal, 40)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal, 40)
                            .multilineTextAlignment(.center)
                    }
                }

                // Toggle between Login and Sign Up
                Button(isLoginMode ? "Need an account? Sign up" : "Already have an account? Log in") {
                    isLoginMode.toggle()
                }
                .font(.footnote)
                .foregroundColor(.white)

                Spacer()
            }
            .padding(.top, 60)
        }
    }

    // MARK: - Helpers
    private func flipSignedInIfSessionValid() async {
        if await SupabaseManager.shared.hasValidSession() {
            await MainActor.run { isSignedIn = true }
        } else {
            // Don’t show an error here; the app’s top-level flow will keep polling/refeshing.
            print("ℹ️ Not flipping isSignedIn yet; session not valid.")
        }
    }

    // MARK: - Apple Sign In with Supabase
    private func handleAppleSignIn(_ authResults: ASAuthorization) {
        guard
            let cred = authResults.credential as? ASAuthorizationAppleIDCredential,
            let identityToken = cred.identityToken,
            let idTokenString = String(data: identityToken, encoding: .utf8)
        else {
            Task { @MainActor in errorMessage = "Apple did not return a valid identity token" }
            return
        }

        Task {
            do {
                let session = try await SupabaseManager.shared.client.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(
                        provider: .apple,
                        idToken: idTokenString,
                        accessToken: nil
                        // nonce: <optional if you generated one>
                    )
                )
                print("✅ Supabase session created for user: \(session.user.id)")
                await flipSignedInIfSessionValid()
            } catch {
                let msg = "Supabase sign-in failed: \(error.localizedDescription)"
                print("❌ \(msg)")
                await MainActor.run { errorMessage = msg }
            }
        }
    }

    // MARK: - Email Sign Up / Log In
    private func emailSignUp() async {
        do {
            // Depending on your Supabase Auth settings, this may or may not return a session immediately.
            let res = try await SupabaseManager.shared.client.auth.signUp(email: email, password: password)
            print("✅ Email user signed up: \(res.user.id)")
            // Try to flip only when a session is actually valid (covers email-confirm flows too)
            await flipSignedInIfSessionValid()
            await MainActor.run { errorMessage = nil }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func emailLogIn() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.signIn(email: email, password: password)
            print("✅ Email user logged in: \(session.user.id)")
            await flipSignedInIfSessionValid()
            await MainActor.run { errorMessage = nil }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}
