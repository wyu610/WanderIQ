# WanderIQ v2 — Sub-project 5c: Web Share UI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring sharing to the web app — a share panel to invite by email + role and list members, plus claiming invites on sign-in — the Preact mirror of iOS 5b, on the 5a backend.

**Architecture:** A `webapp/src/supabase/sharing.ts` module over the existing `supabase` client: `listMembers` (`select().eq("trip_id")`), `addMember` (`insert` a pending row), `claimInvites` (`rpc("claim_invites")`). A `ShareView` Preact component (members list + invite form) toggled from `TripDetailView`. `ui/store.ts`'s `startSync()` calls `claimInvites()` before the first pull. Integration code: build-verified; real add/list/claim runtime is user-gated (signed-in session), same as the rest of the web flow.

**Tech Stack:** supabase-js (`from`/`insert`/`select`/`eq`/`rpc` — verified in 4c), Preact, Vitest (42 tests unchanged).

**Spec:** design §9.1. iOS equivalent = 5b (merged).

**Verification:** `cd webapp && npm test` (42, unchanged) + `npm run build`. Runtime via the browser once signed in (user).

---

### Task 1: Web sharing module

**Files:**
- Create: `webapp/src/supabase/sharing.ts`

- [ ] **Step 1: Write the module**

Create `webapp/src/supabase/sharing.ts`:
```ts
import { supabase } from "./client";

export interface TripMember {
  id: string;
  role: string;            // "viewer" | "editor"
  status: string;          // "pending" | "accepted"
  invited_email: string | null;
  user_id: string | null;
}

/** Members of a trip (RLS returns only rows the caller may see). */
export async function listMembers(tripId: string): Promise<TripMember[]> {
  const { data, error } = await supabase.from("trip_members")
    .select("id, role, status, invited_email, user_id")
    .eq("trip_id", tripId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return (data ?? []) as TripMember[];
}

/** Owner adds a pending invite (owner-gated by RLS). */
export async function addMember(tripId: string, email: string, role: string): Promise<void> {
  const { error } = await supabase.from("trip_members")
    .insert({ trip_id: tripId, invited_email: email, role, status: "pending" });
  if (error) throw error;
}

/** Link this user to pending invites for their email (5a backend). */
export async function claimInvites(): Promise<void> {
  const { error } = await supabase.rpc("claim_invites");
  if (error) throw error;
}
```

- [ ] **Step 2: Build + tests**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm run build && npm test
```
Expected: build succeeds (tsc type-checks the supabase-js calls); 42 tests still pass. If tsc rejects `.insert(...)`, `.eq(...)`, or `.rpc(...)`, report exact (BLOCKED).

- [ ] **Step 3: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/supabase/sharing.ts
git commit -m "feat(web): sharing module (add/list members, claim invites)"
```

---

### Task 2: ShareView + wire into TripDetailView

**Files:**
- Create: `webapp/src/ui/ShareView.tsx`
- Modify: `webapp/src/ui/TripDetailView.tsx`, `webapp/src/ui/styles.css`

- [ ] **Step 1: Write ShareView**

Create `webapp/src/ui/ShareView.tsx`:
```tsx
import { useEffect, useState } from "preact/hooks";
import { addMember, listMembers, type TripMember } from "../supabase/sharing";

export function ShareView({ tripId, onClose }: { tripId: string; onClose: () => void }) {
  const [members, setMembers] = useState<TripMember[]>([]);
  const [email, setEmail] = useState("");
  const [role, setRole] = useState("editor");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function load() {
    try { setMembers(await listMembers(tripId)); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
  }
  useEffect(() => { void load(); }, [tripId]);

  async function add(e: Event) {
    e.preventDefault();
    setBusy(true); setError(null);
    try {
      await addMember(tripId, email.trim(), role);
      setEmail("");
      await load();
    } catch (err) { setError(err instanceof Error ? err.message : String(err)); }
    finally { setBusy(false); }
  }

  return (
    <section class="share">
      <header><h2>Share Trip</h2><button class="link" onClick={onClose}>Done</button></header>
      <ul>
        {members.length === 0
          ? <li class="muted">No one yet</li>
          : members.map((m) => (
              <li key={m.id}>{m.invited_email ?? "member"} <span class="muted">· {m.role} · {m.status}</span></li>
            ))}
      </ul>
      <form onSubmit={add}>
        <input type="email" placeholder="Email" value={email}
               onInput={(e) => setEmail((e.target as HTMLInputElement).value)} />
        <select value={role} onChange={(e) => setRole((e.target as HTMLSelectElement).value)}>
          <option value="editor">Editor</option>
          <option value="viewer">Viewer</option>
        </select>
        <button type="submit" disabled={busy || !email}>Add</button>
      </form>
      {error && <p class="error">{error}</p>}
    </section>
  );
}
```

- [ ] **Step 2: Wire into TripDetailView**

In `webapp/src/ui/TripDetailView.tsx`: import `ShareView`, add `const [sharing, setSharing] = useState(false);`, add a Share button next to the Back button, and when `sharing` render `<ShareView>` instead of the tabs. Concretely, in the early `if (!trip)` guard keep it; then near the top of the returned `<main class="tripdetail">` add a Share entry, and short-circuit to ShareView when sharing. Add after the `← Back` button:
```tsx
      <button class="link" onClick={() => setSharing(true)}>Share</button>
```
and immediately after computing `trip` (before the tabs JSX), add:
```tsx
  if (sharing) return (
    <main class="tripdetail">
      <ShareView tripId={tripId} onClose={() => setSharing(false)} />
    </main>
  );
```
(Place the `sharing` short-circuit after the `if (!trip)` guard so `trip` is known; the `useState` import already comes from "preact/hooks".)

- [ ] **Step 3: Styles**

Append to `webapp/src/ui/styles.css`:
```css
.share header { display: flex; justify-content: space-between; align-items: center; }
.share ul { list-style: none; padding: 0; }
.share .muted { color: #888; font-size: .85em; }
.share form { display: flex; gap: 8px; margin-top: 8px; }
.share input { flex: 1; padding: 8px; }
```

- [ ] **Step 4: Build + tests**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm run build && npm test
```
Expected: build succeeds; 42 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/ui/ShareView.tsx webapp/src/ui/TripDetailView.tsx webapp/src/ui/styles.css
git commit -m "feat(web): share panel in trip detail"
```

---

### Task 3: Claim invites on sign-in

**Files:**
- Modify: `webapp/src/ui/store.ts`

- [ ] **Step 1: Claim before the first pull**

In `webapp/src/ui/store.ts`, import `claimInvites` and call it at the start of
`startSync()` (before `await coordinator.start()`), tolerating failure:
```ts
import { claimInvites } from "../supabase/sharing";
```
and inside `startSync()`, as the first line:
```ts
  try { await claimInvites(); } catch { /* non-fatal; retried next sign-in */ }
```

- [ ] **Step 2: Build + tests**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm run build && npm test
```
Expected: build succeeds; 42 tests pass.

- [ ] **Step 3: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/ui/store.ts
git commit -m "feat(web): claim email invites on sign-in"
```

---

### Task 4: Runtime verification (USER — browser, two accounts)

**Files:** none

Requires signed-in sessions. Mirrors iOS 5b T4.

- [ ] **Step 1: Owner invites, participant claims**

In one browser (account A, owner): open a trip → Share → add account B's email as
Editor. In another browser/profile (account B, same email): sign in — `claimInvites`
runs in `startSync` before the pull, so the shared trip appears. Confirm B can edit
and edits propagate to A (Realtime).

- [ ] **Step 2: Confirm server-side** (same `psql` check as iOS 5b T4: the
  `trip_members` row flips to `accepted`).

- [ ] **Step 3: Report results** (no commit). Defects = real integration bugs.

---

## Done criteria

- `cd webapp && npm test` (42) + `npm run build` pass.
- `ShareView` reachable from a trip; `sharing.ts` add/list/claim compile.
- `claimInvites()` runs in `startSync()` before the first pull.
- Two-account browser runtime verified by the user (Task 4).
- **This completes sub-project 5 (sharing) on both clients.** Only **sub-project
  6 — import/export (JSON + CSV)** remains in the v2 build.

## Notes for SP6 / later

- Owner-only share affordance + member removal are the same follow-ups noted for
  iOS 5b (need `owner_id` surfaced client-side).
- Optional invite-notification email (Edge Function) remains deferred.
