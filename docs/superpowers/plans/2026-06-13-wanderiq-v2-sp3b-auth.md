# WanderIQ v2 — Sub-project 3b: Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate the app behind Supabase Auth — email/password (live now), plus Sign in with Apple and Google (wired, activated once OAuth providers are configured) — with one shared `SupabaseClient` whose session persists in the Keychain and drives a sign-in/sign-out UI.

**Architecture:** Introduce a single shared `SupabaseClient` (`AppSupabase.client`) used by BOTH auth and the 3a transport, so they share one persisted session. An `@MainActor @Observable AuthController` exposes `isSignedIn` and the sign-in/up/out actions and tracks `auth.authStateChanges`. `WanderIQApp` shows `AuthView` when signed out and the existing `TripListView` when signed in. Auth is integration/UI code: it is build-verified and manually smoke-tested (an email sign-up against the dev cloud creates a real `auth.users` row and, via the sub-project-1 trigger, a `profiles` row — a concrete end-to-end check).

**Tech Stack:** supabase-swift (Auth), SwiftUI, AuthenticationServices (Sign in with Apple), XcodeGen.

**Spec:** design §7 (auth: Apple/Google/email). Verified supabase-swift Auth API: `auth.signIn(email:password:)`, `auth.signUp(email:password:)`, `auth.signInWithIdToken(credentials:.init(provider:.apple,idToken:))`, `auth.signInWithOAuth(provider:.google,redirectTo:)`, `auth.authStateChanges` (AsyncStream of `(event, session)`), `auth.session`, `auth.signOut()`.

**Prerequisites (USER):**
1. **Email testing:** in the Supabase dashboard → Authentication → Providers → Email, turn **"Confirm email" OFF** for the dev project so `signUp` returns a session immediately (otherwise sign-up waits on an email link). Re-enable for production later.
2. **Apple/Google buttons** only function once their providers are configured (the deferred Task 10) AND the app has the Sign in with Apple capability (Task 5 here). Email needs neither.

**Verification:** package `cd WanderIQKit && make test` (67, unchanged — 3b adds no package code); app build `xcodegen generate && xcodebuild ... build`; manual: email sign-up in the simulator → app shows the trip list → a `profiles` row exists (check via `psql "$SUPABASE_DB_URL" -c "select count(*) from profiles;"`).

---

### Task 1: Shared SupabaseClient + refactor the transport to use it

**Files:**
- Create: `WanderIQ/Sync/AppSupabase.swift`
- Modify: `WanderIQ/Sync/SupabaseRemoteSyncBackend.swift`

- [ ] **Step 1: Create the shared client**

Create `WanderIQ/Sync/AppSupabase.swift`:
```swift
import Foundation
import Supabase

/// The single app-wide Supabase client. Auth and the sync transport share it
/// so they share one Keychain-persisted session. supabase-swift defaults to
/// KeychainLocalStorage for auth on Apple platforms, so sessions survive
/// relaunches automatically.
enum AppSupabase {
    static let client = SupabaseClient(supabaseURL: SupabaseConfig.url,
                                       supabaseKey: SupabaseConfig.anonKey)
}
```

- [ ] **Step 2: Point the backend at the shared client**

In `WanderIQ/Sync/SupabaseRemoteSyncBackend.swift`, replace the `convenience init()` that builds its own client:
```swift
    convenience init() {
        self.init(client: SupabaseClient(supabaseURL: SupabaseConfig.url,
                                         supabaseKey: SupabaseConfig.anonKey))
    }
```
with:
```swift
    convenience init() {
        self.init(client: AppSupabase.client)
    }
```

- [ ] **Step 3: Build and commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)|error:' | head -5
git add WanderIQ/Sync/AppSupabase.swift WanderIQ/Sync/SupabaseRemoteSyncBackend.swift
git commit -m "refactor(ios): single shared SupabaseClient for auth + sync"
```
Expected: `** BUILD SUCCEEDED **`. Do NOT commit generated/gitignored files.

---

### Task 2: AuthController

**Files:**
- Create: `WanderIQ/Auth/AuthController.swift`

- [ ] **Step 1: Create the controller**

Create `WanderIQ/Auth/AuthController.swift`:
```swift
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
                case .signedOut:
                    self.phase = .signedOut; self.userEmail = nil
                case .passwordRecovery:
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

    /// idToken from ASAuthorizationAppleIDCredential (see AuthView).
    func signInWithApple(idToken: String, fullName: String?) async {
        await run {
            _ = try await self.client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken))
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
```

- [ ] **Step 2: Build and commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)|error:' | head -5
git add WanderIQ/Auth/AuthController.swift
git commit -m "feat(ios): AuthController over Supabase auth state"
```
Expected: `** BUILD SUCCEEDED **`.

---

### Task 3: AuthView (email + Apple + Google)

**Files:**
- Create: `WanderIQ/Auth/AuthView.swift`

- [ ] **Step 1: Create the sign-in UI**

Create `WanderIQ/Auth/AuthView.swift`:
```swift
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

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        guard case let .success(authResult) = result,
              let cred = authResult.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else { return }
        await auth.signInWithApple(idToken: idToken, fullName: cred.fullName?.formatted())
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)|error:' | head -5
git add WanderIQ/Auth/AuthView.swift
git commit -m "feat(ios): AuthView with email, Apple, and Google sign-in"
```
Expected: `** BUILD SUCCEEDED **`.

---

### Task 4: Gate the app behind auth

**Files:**
- Modify: `WanderIQ/App/WanderIQApp.swift`

- [ ] **Step 1: Drive the root view from AuthController**

In `WanderIQ/App/WanderIQApp.swift`, add `@State private var auth = AuthController()` to the `WanderIQApp` struct (next to `@State private var model = AppModel()`), and replace the `WindowGroup { ... }` body with:
```swift
        WindowGroup {
            Group {
                switch auth.phase {
                case .loading:
                    ProgressView()
                case .signedOut:
                    AuthView()
                case .signedIn:
                    TripListView().environment(model)
                }
            }
            .environment(auth)
        }
```

- [ ] **Step 2: Build and commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)|error:' | head -5
git add WanderIQ/App/WanderIQApp.swift
git commit -m "feat(ios): gate app behind authentication"
```
Expected: `** BUILD SUCCEEDED **`.

---

### Task 5: Sign in with Apple capability + Google redirect scheme

**Files:**
- Modify: `WanderIQ.entitlements`
- Modify: `project.yml`

- [ ] **Step 1: Add the Apple sign-in entitlement**

In `project.yml`, under the `WanderIQ` target `entitlements.properties` (which currently has the iCloud + aps-environment keys), add:
```yaml
        com.apple.developer.applesignin: [Default]
```

- [ ] **Step 2: Add the Google OAuth redirect URL scheme**

In `project.yml`, under the `WanderIQ` target `info.properties`, add a URL types entry so the `com.wanderiq://` callback returns to the app:
```yaml
        CFBundleURLTypes:
          - CFBundleURLSchemes: [com.wanderiq]
```

- [ ] **Step 3: Regenerate, build, and commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)|error:' | head -5
git add project.yml WanderIQ.entitlements
git commit -m "chore(ios): Sign in with Apple entitlement + OAuth redirect scheme"
```
Expected: `** BUILD SUCCEEDED **`. (XcodeGen writes the entitlement into WanderIQ.entitlements, which IS tracked.)

> Note: the `applesignin` entitlement requires the App ID to have the Sign in
> with Apple capability enabled in the Apple Developer portal. Automatic signing
> adds it when building to a device; the simulator build does not enforce it.

---

### Task 6: Manual end-to-end verification (email)

**Files:** none

Requires the email-confirmation prerequisite (OFF) and a populated
`Supabase.xcconfig`.

- [ ] **Step 1: Run the app and sign up with email**

Build to a booted simulator, launch the app. The app shows `AuthView`. Choose
"Sign Up", enter a test email (e.g. `test1@wanderiq.dev`) and a password, tap
Create Account. Expected: the view switches to the trip list (the seeded China
trip), confirming `signUp` returned a session and gating flipped to `.signedIn`.

- [ ] **Step 2: Confirm the profile row was created server-side**

Run:
```bash
cd /Users/wyu610/_Dev/WanderIQ
source .env
/opt/homebrew/opt/libpq/bin/psql "$SUPABASE_DB_URL" -tAc \
  "select count(*) from profiles;"
```
Expected: `1` (or more) — the sub-project-1 `handle_new_user` trigger created a
`profiles` row for the new auth user. This verifies auth → DB end-to-end.

- [ ] **Step 3: Confirm sign-out returns to AuthView**

Add a temporary toolbar Sign Out button (or call `auth.signOut()` from a debug
hook), tap it, and confirm the app returns to `AuthView`. (A permanent sign-out
control lands in 3c's settings surface.)

---

## Done criteria

- App builds; launching signed-out shows `AuthView`, signed-in shows the trip list.
- Email sign-up against the dev cloud creates an `auth.users` + `profiles` row and
  flips the app to signed-in (manual verification).
- Apple/Google buttons compile and are wired; they function once their providers
  are configured in Supabase (Task 10) and (for Apple) the capability is enabled
  on the App ID.
- Package tests remain 67 (3b adds no package code).
- Next plan: **3c — App cutover** (wire SyncEngine capture/push/pull into
  AppModel using the now-authenticated shared client; file-persist Outbox +
  SyncState; Realtime → pull; retire CloudKit).

## Notes for 3c

- The shared `AppSupabase.client` now holds the authenticated session; 3c's
  AppModel sync wiring uses `SupabaseRemoteSyncBackend()` (which reads that
  client) and only pushes/pulls when `auth.phase == .signedIn`.
- Email confirmation should be re-enabled before production; consider adding
  password-reset (the `.passwordRecovery` event is already handled as a no-op).
