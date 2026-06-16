import SwiftUI

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
                if let err = auth.lastError {
                    Section { Text(err).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("WanderIQ")
        }
    }

    private func submit() async {
        busy = true; defer { busy = false }
        switch mode {
        case .signIn: await auth.signIn(email: email, password: password)
        case .signUp: await auth.signUp(email: email, password: password)
        }
    }
}
