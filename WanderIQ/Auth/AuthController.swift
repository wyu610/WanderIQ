import Foundation
import Supabase
import Observation

/// Observable wrapper over the shared client's auth. Drives root gating and
/// exposes the sign-in/up/out actions. Tracks authStateChanges so the UI
/// updates on sign-in, sign-out, token refresh, and the restored session.
@MainActor
@Observable
final class AuthController {
    enum Phase: Equatable { case loading, signedOut, signedIn }

    private(set) var phase: Phase = .loading
    private(set) var userEmail: String?
    var lastError: String?

    @ObservationIgnored private let client = AppSupabase.client
    @ObservationIgnored private var watch: Task<Void, Never>?

    init() {
        watch = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                switch event {
                case .signedIn, .initialSession, .tokenRefreshed, .userUpdated:
                    self.apply(session)
                case .signedOut, .userDeleted:
                    self.phase = .signedOut; self.userEmail = nil
                case .passwordRecovery, .mfaChallengeVerified:
                    break
                }
            }
        }
    }

    private func apply(_ session: Session?) {
        if let session {
            userEmail = session.user.email
            phase = .signedIn
        } else {
            phase = .signedOut
        }
    }

    func signIn(email: String, password: String) async {
        await run { try await self.client.auth.signIn(email: email, password: password) }
    }

    func signUp(email: String, password: String) async {
        await run { _ = try await self.client.auth.signUp(email: email, password: password) }
    }

    func signOut() async {
        await run { try await self.client.auth.signOut() }
    }

    /// idToken from ASAuthorizationAppleIDCredential (see AuthView). `nonce` is
    /// the RAW nonce whose SHA-256 was set on the Apple request — required by
    /// GoTrue to verify the id-token and prevent replay.
    func signInWithApple(idToken: String, nonce: String, fullName: String?) async {
        await run {
            _ = try await self.client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
        }
    }

    func signInWithGoogle() async {
        await run {
            _ = try await self.client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "com.wanderiq://auth-callback"))
        }
    }

    private func run(_ op: @escaping () async throws -> Void) async {
        lastError = nil
        do { try await op() }
        catch { lastError = error.localizedDescription }
    }

    deinit { watch?.cancel() }
}
