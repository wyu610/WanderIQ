import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(AuthController.self) private var auth
    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn
    @State private var busy = false

    enum Mode { case signIn, signUp }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                }
                Section {
                    Button(mode == .signIn ? "Sign In" : "Create Account") {
                        Task { await submit() }
                    }
                    .disabled(busy || email.isEmpty || password.isEmpty)
                    Button(mode == .signIn ? "Need an account? Sign Up"
                                           : "Have an account? Sign In") {
                        mode = mode == .signIn ? .signUp : .signIn
                    }
                    .font(.footnote)
                }
                Section("Or") {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task { await handleApple(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)

                    Button("Continue with Google") {
                        Task { await auth.signInWithGoogle() }
                    }
                }
                if let err = auth.lastError {
                    Section { Text(err).foregroundStyle(.red).font(.footnote) }
                }
            }
            .warmCanvas()
            .safeAreaInset(edge: .top) {
                VStack(spacing: 4) {
                    Text("WanderIQ")
                        .font(.system(size: 38, weight: .bold, design: .serif))
                        .foregroundStyle(Color.wInk)
                    Text("Plan trips together.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                .padding(.bottom, 12)
                .background(Color.wSand)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func submit() async {
        busy = true; defer { busy = false }
        switch mode {
        case .signIn: await auth.signIn(email: email, password: password)
        case .signUp: await auth.signUp(email: email, password: password)
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        guard case let .success(authResult) = result,
              let cred = authResult.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else { return }
        await auth.signInWithApple(idToken: idToken, fullName: cred.fullName?.formatted())
    }
}
