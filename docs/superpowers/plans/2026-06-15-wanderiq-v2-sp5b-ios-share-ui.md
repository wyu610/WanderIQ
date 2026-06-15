# WanderIQ v2 — Sub-project 5b: iOS Share UI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-enable sharing in the iOS app — a share sheet to invite a member by email + role and list members, plus claiming email invites on sign-in — using the 5a backend.

**Architecture:** App-target `SharingService` over `AppSupabase.client`: `addMember` inserts a pending `trip_members` row (owner-gated by RLS), `members` selects the trip's membership, `claimInvites` calls the `claim_invites` RPC. A `ShareView` SwiftUI sheet presents both, re-attached to `TripDetailView`'s toolbar (the share button removed in 3c). `SupabaseSyncCoordinator.start()` calls `claimInvites()` before its first pull so newly-granted trips appear. Integration code: build-verified; real add/list/claim needs an authenticated session (the user's pending email-auth verification), so runtime is user-gated.

**Tech Stack:** supabase-swift (rpc/insert/select verified), SwiftUI, XcodeGen.

**Spec:** design §9.1 (per-trip email invite + viewer/editor roles). Web equivalent = 5c.

**Scope note:** functional-first. The share button is shown for any trip; non-owner *add* attempts fail under RLS and surface an error (the client doesn't yet track `owner_id` — an "owner-only share button" refinement can follow once owner info is in the model).

**Verification:** package `cd WanderIQKit && make test` (unchanged); app build `xcodegen generate && xcodebuild ... build`. Runtime (add/list/claim) verified by the user once signed in.

---

### Task 1: SharingService + TripMember

**Files:**
- Create: `WanderIQ/Sync/SharingService.swift`

- [ ] **Step 1: Write the service**

Create `WanderIQ/Sync/SharingService.swift`:
```swift
import Foundation
import Supabase

/// A trip_members row (subset) for display. Property names match the Postgres
/// columns (supabase-swift's decoder does not convert snake_case).
struct TripMember: Decodable, Identifiable, Sendable {
    let id: UUID
    let role: String          // "viewer" | "editor"
    let status: String        // "pending" | "accepted"
    let invited_email: String?
    let user_id: UUID?
}

/// Per-trip sharing over Supabase. Add/list are owner-gated by RLS;
/// claimInvites links this user to pending invites for their email.
@MainActor
final class SharingService {
    private let client = AppSupabase.client

    func members(tripID: UUID) async throws -> [TripMember] {
        try await client.from("trip_members")
            .select("id, role, status, invited_email, user_id")
            .eq("trip_id", value: tripID.uuidString.lowercased())
            .order("created_at", ascending: true)
            .execute().value
    }

    func addMember(tripID: UUID, email: String, role: String) async throws {
        struct NewMember: Encodable {
            let trip_id: String
            let invited_email: String
            let role: String
            let status: String
        }
        try await client.from("trip_members").insert(
            NewMember(trip_id: tripID.uuidString.lowercased(),
                      invited_email: email, role: role, status: "pending")
        ).execute()
    }

    func claimInvites() async throws {
        _ = try await client.rpc("claim_invites").execute()
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/wyu610/_Dev/WanderIQ
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)|error:' | head -8
```
Expected: `** BUILD SUCCEEDED **`. If supabase-swift rejects `.rpc(...).execute()`, `.insert(...).execute()`, or `.eq(...)`, report exact (BLOCKED) — verified against v2 docs.

- [ ] **Step 3: Commit**

```bash
git add WanderIQ/Sync/SharingService.swift
git commit -m "feat(ios): SharingService (add/list members, claim invites)"
```

---

### Task 2: ShareView + re-attach the trip-detail share button

**Files:**
- Create: `WanderIQ/Features/Sharing/ShareView.swift`
- Modify: `WanderIQ/Features/TripDetail/TripDetailView.swift`

- [ ] **Step 1: Write ShareView**

Create `WanderIQ/Features/Sharing/ShareView.swift`:
```swift
import SwiftUI

struct ShareView: View {
    let tripID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var members: [TripMember] = []
    @State private var email = ""
    @State private var role = "editor"
    @State private var error: String?
    @State private var busy = false
    private let service = SharingService()

    var body: some View {
        NavigationStack {
            Form {
                Section("People") {
                    if members.isEmpty {
                        Text("No one yet").foregroundStyle(.secondary)
                    }
                    ForEach(members) { m in
                        HStack {
                            Text(m.invited_email ?? "member")
                            Spacer()
                            Text("\(m.role) · \(m.status)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Invite by email") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Role", selection: $role) {
                        Text("Editor").tag("editor")
                        Text("Viewer").tag("viewer")
                    }
                    Button("Add") { Task { await add() } }
                        .disabled(busy || email.isEmpty)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Share Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task { await load() }
        }
    }

    private func load() async {
        do { members = try await service.members(tripID: tripID) }
        catch { self.error = error.localizedDescription }
    }

    private func add() async {
        busy = true; defer { busy = false }
        self.error = nil
        do {
            try await service.addMember(tripID: tripID,
                                        email: email.trimmingCharacters(in: .whitespaces),
                                        role: role)
            email = ""
            await load()
        } catch { self.error = error.localizedDescription }
    }
}
```

- [ ] **Step 2: Re-attach the share button in TripDetailView**

In `WanderIQ/Features/TripDetail/TripDetailView.swift`, add a `@State private var showingShare = false` to the struct, and on the `TabView` (after `.navigationBarTitleDisplayMode(.inline)`) add a toolbar button + sheet:
```swift
            .toolbar {
                Button { showingShare = true } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
                .accessibilityLabel("Share Trip")
            }
            .sheet(isPresented: $showingShare) { ShareView(tripID: tripID) }
```
(The view currently has no toolbar after the 3c CloudKit removal; this restores a share entry point.)

- [ ] **Step 3: Build + commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)|error:' | head -8
git add WanderIQ/Features/Sharing/ShareView.swift WanderIQ/Features/TripDetail/TripDetailView.swift
git commit -m "feat(ios): share sheet + trip-detail share button"
```
Expected: `** BUILD SUCCEEDED **`.

---

### Task 3: Claim invites on sync start

**Files:**
- Modify: `WanderIQ/Sync/SupabaseSyncCoordinator.swift`

- [ ] **Step 1: Claim before the first pull**

In `WanderIQ/Sync/SupabaseSyncCoordinator.swift`, in `start()`, add a claim call
before `await fetchNow()`:
```swift
    func start() async {
        guard isAuthed else { return }
        try? await SharingService().claimInvites()
        await fetchNow()
        subscribeRealtime()
    }
```
(`try?` — a claim failure must not block sync; the next start retries.)

- [ ] **Step 2: Build + commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)|error:' | head -8
git add WanderIQ/Sync/SupabaseSyncCoordinator.swift
git commit -m "feat(ios): claim email invites on sync start"
```
Expected: `** BUILD SUCCEEDED **`.

---

### Task 4: Runtime verification (USER — two accounts)

**Files:** none

Requires signed-in sessions (the pending email-auth verification). The first
true test of sharing across the iOS app.

- [ ] **Step 1: Owner invites, participant claims**

On account A (owner) in the app: open a trip → Share → add account B's email as
Editor. On account B (signed in, same email): relaunch — `claimInvites()` runs on
start, then the pull brings in the shared trip. Confirm B sees A's trip and can
edit items (editor), and that edits propagate back to A (Realtime).

- [ ] **Step 2: Confirm server-side**

```bash
cd /Users/wyu610/_Dev/WanderIQ; source .env
/opt/homebrew/opt/libpq/bin/psql "$SUPABASE_DB_URL" -tAc \
  "select status, role from trip_members where invited_email ilike '%' order by created_at desc limit 3;"
```
Expected: the invite row shows `accepted` + the role after B claims.

- [ ] **Step 3: Report results** (no commit). Any defect is a real integration bug to fix.

---

## Done criteria

- App builds; `ShareView` is reachable from a trip's toolbar; `SharingService`
  add/list/claim compile against supabase-swift.
- `claimInvites()` runs on sync start.
- Package tests unchanged.
- Two-account runtime verified by the user (Task 4) before relying on it.
- Next: **5c** — the web share UI (Preact equivalent: a share panel calling the
  same insert/select + `claim_invites` rpc via supabase-js). Then **6** —
  import/export.

## Notes for 5c / later

- 5c mirrors this with supabase-js: `from("trip_members").insert(...)`,
  `.select(...).eq("trip_id", …)`, `rpc("claim_invites")`; call claim in the web
  store's `startSync()` before the first pull.
- Owner-only share affordance + member removal (owner `delete` on trip_members)
  are sensible follow-ups once `owner_id` is surfaced to the clients.
