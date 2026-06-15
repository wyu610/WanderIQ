# WanderIQ v2 — Sub-project 4d: Web UI + PWA

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the web app a face — Preact UI (auth screen + prep/itinerary/packing views) wired to `WebAuth` + `WebSyncCoordinator` + the `Trip` model, reactive to sync/Realtime via signals, installable as a PWA — then verify the first real end-to-end sign-in→edit→sync in a browser.

**Architecture:** Preact + `@preact/signals` in `webapp/`. A small **UI store** (`ui/store.ts`) bridges the framework-agnostic engine to the framework: it holds a `trips` signal + an `auth` signal, subscribes to a new `WebSyncCoordinator.onChange` hook and to `WebAuth.onChange`, and exposes actions (`createTrip`, `editTrip`, `toggleItem`, …) that call `coordinator.noteLocalChange`. Components read signals and re-render automatically. The app gates on auth (signedOut→`AuthView`, signedIn→`TripListView`/`TripDetailView`). PWA via a manifest + a cache-first service worker. UI is build- + browser-verified (Playwright headless smoke + a manual signed-in run), not unit-tested.

**Tech Stack:** Preact, `@preact/signals`, `@preact/preset-vite` (verified: plugin in `vite.config.ts`, tsconfig `jsx:"react-jsx"`/`jsxImportSource:"preact"`), Vitest (existing 42 tests unchanged), Playwright MCP (e2e smoke).

**Spec:** design §8.2 (feature parity: prep/itinerary/packing, installable PWA). UI twin of the SwiftUI views.

**Prerequisite (USER, for Task 7 runtime only):** a real `webapp/.env` (anon key + URL) and the dev project with "Confirm email" off, so the signed-in e2e run works. Tasks 1–6 build/render with the placeholder `.env`.

**Verification:** `cd webapp && npm test` (42, unchanged) + `npm run build`; Task 7 = browser/Playwright.

**Scope note:** functional-first UI (correct behavior + clean layout), not a pixel re-creation of the old `trip-webapp` styling; visual polish/bilingual strings can follow.

---

### Task 1: Preact + signals toolchain

**Files:**
- Modify: `webapp/package.json`, `webapp/tsconfig.json`
- Create: `webapp/vite.config.ts`
- Delete: `webapp/vitest.config.ts`
- Modify: `webapp/src/main.ts` → `webapp/src/main.tsx`

- [ ] **Step 1: Install Preact**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm install preact @preact/signals
npm install -D @preact/preset-vite
```

- [ ] **Step 2: vite.config.ts (plugin + test config), remove vitest.config.ts**

Create `webapp/vite.config.ts`:
```ts
import { defineConfig } from "vite";
import preact from "@preact/preset-vite";

export default defineConfig({
  plugins: [preact()],
  test: { globals: true, environment: "node" },
});
```
Delete `webapp/vitest.config.ts` (Vitest reads `vite.config.ts`):
```bash
git rm webapp/vitest.config.ts
```

- [ ] **Step 3: tsconfig JSX**

In `webapp/tsconfig.json` `compilerOptions`, add:
```json
    "jsx": "react-jsx",
    "jsxImportSource": "preact",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
```

- [ ] **Step 4: Convert the entry to TSX**

```bash
git mv webapp/src/main.ts webapp/src/main.tsx
```
Replace `webapp/src/main.tsx` content:
```tsx
import { render } from "preact";

function App() {
  return <h1>WanderIQ</h1>;
}

render(<App />, document.getElementById("app")!);
```
Update `webapp/index.html`'s script src from `/src/main.ts` to `/src/main.tsx`.

- [ ] **Step 5: Verify build + tests**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm test
npm run build
```
Expected: 42 tests still pass (node-env, unaffected by the Preact plugin); `npm run build` produces `dist/` with the rendered `<h1>`. The Vite preview (`npm run preview`) would show "WanderIQ".

- [ ] **Step 6: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
# Captures the new/changed files plus the main.ts→main.tsx rename and the
# vitest.config.ts deletion already staged via git mv / git rm above.
git add -A webapp
git commit -m "chore(web): Preact + signals toolchain"
```

---

### Task 2: Coordinator onChange hook + reactive UI store

**Files:**
- Modify: `webapp/src/sync/webSyncCoordinator.ts`
- Create: `webapp/src/ui/store.ts`

- [ ] **Step 1: Add an `onChange` hook to the coordinator**

In `webapp/src/sync/webSyncCoordinator.ts`, add a public callback property and
fire it whenever state changes. Add near the other private fields:
```ts
  onChange: (() => void) | undefined;
```
Add a private notifier and call it at the end of `noteLocalChange`, `fetchNow`,
and `flush` (after `persist`):
```ts
  private notify(): void { this.onChange?.(); }
```
- In `noteLocalChange`, after `this.schedulePush();` add `this.notify();`
- In `fetchNow`, after `await this.persist();` add `this.notify();`
- In `flush`, after the final `await this.persist();` add `this.notify();`

- [ ] **Step 2: Create the reactive store**

Create `webapp/src/ui/store.ts`:
```ts
import { signal } from "@preact/signals";
import { WebAuth, type Phase } from "../auth/webAuth";
import { WebSyncCoordinator } from "../sync/webSyncCoordinator";
import { newTrip, type ChecklistItem, type ItemKind, type Trip } from "../model/trip";

export const authPhase = signal<Phase>("loading");
export const trips = signal<Trip[]>([]);

const auth = new WebAuth();
let coordinator: WebSyncCoordinator | undefined;

auth.onChange(() => {
  authPhase.value = auth.phase;
  if (auth.isSignedIn && !coordinator) void startSync();
});

async function startSync(): Promise<void> {
  coordinator = new WebSyncCoordinator();
  coordinator.onChange = () => { trips.value = [...coordinator!.state.trips.values()]; };
  await coordinator.start();
  trips.value = [...coordinator.state.trips.values()];
}

export const authActions = {
  signIn: (e: string, p: string) => auth.signIn(e, p),
  signUp: (e: string, p: string) => auth.signUp(e, p),
  google: () => auth.signInWithGoogle(),
  apple: () => auth.signInWithApple(),
  signOut: () => auth.signOut(),
};

function commit(next: Trip): void {
  const old = coordinator?.state.trips.get(next.id);
  next.modifiedAt = Math.floor(Date.now() / 1000);
  coordinator?.noteLocalChange(old, next);
}

export const tripActions = {
  create(name: string, start: number, end: number): void {
    commit(newTrip({ name, startDate: start, endDate: end }));
  },
  toggleItem(tripId: string, itemId: string): void {
    const t = coordinator?.state.trips.get(tripId);
    if (!t) return;
    const next: Trip = structuredClone(t);
    const it = next.items.find((x) => x.id === itemId);
    if (!it) return;
    it.isDone = !it.isDone;
    it.modifiedAt = Math.floor(Date.now() / 1000);
    commit(next);
  },
  addItem(tripId: string, kind: ItemKind, label: string): void {
    const t = coordinator?.state.trips.get(tripId);
    if (!t) return;
    const next: Trip = structuredClone(t);
    const item: ChecklistItem = { id: crypto.randomUUID(), kind, label, notes: "",
      isDone: false, sortOrder: next.items.length, modifiedAt: Math.floor(Date.now() / 1000) };
    next.items.push(item);
    commit(next);
  },
};
```

- [ ] **Step 3: Build + tests**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm run build && npm test
```
Expected: build succeeds; 42 tests still pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/sync/webSyncCoordinator.ts webapp/src/ui/store.ts
git commit -m "feat(web): coordinator onChange hook + reactive UI store"
```

---

### Task 3: Auth view + root gating

**Files:**
- Create: `webapp/src/ui/AuthView.tsx`, `webapp/src/ui/App.tsx`
- Modify: `webapp/src/main.tsx`

- [ ] **Step 1: AuthView**

Create `webapp/src/ui/AuthView.tsx`:
```tsx
import { useState } from "preact/hooks";
import { authActions } from "./store";

export function AuthView() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [mode, setMode] = useState<"in" | "up">("in");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: Event) {
    e.preventDefault();
    setBusy(true); setError(null);
    const err = mode === "in"
      ? await authActions.signIn(email, password)
      : await authActions.signUp(email, password);
    setBusy(false);
    if (err) setError(err);
  }

  return (
    <main class="auth">
      <h1>WanderIQ</h1>
      <form onSubmit={submit}>
        <input type="email" placeholder="Email" value={email}
               onInput={(e) => setEmail((e.target as HTMLInputElement).value)} />
        <input type="password" placeholder="Password" value={password}
               onInput={(e) => setPassword((e.target as HTMLInputElement).value)} />
        <button type="submit" disabled={busy || !email || !password}>
          {mode === "in" ? "Sign In" : "Create Account"}
        </button>
      </form>
      <button class="link" onClick={() => setMode(mode === "in" ? "up" : "in")}>
        {mode === "in" ? "Need an account? Sign Up" : "Have an account? Sign In"}
      </button>
      <div class="oauth">
        <button onClick={() => void authActions.apple()}>Sign in with Apple</button>
        <button onClick={() => void authActions.google()}>Continue with Google</button>
      </div>
      {error && <p class="error">{error}</p>}
    </main>
  );
}
```

- [ ] **Step 2: App (gating) + entry**

Create `webapp/src/ui/App.tsx`:
```tsx
import { authPhase } from "./store";
import { AuthView } from "./AuthView";
import { TripListView } from "./TripListView";

export function App() {
  switch (authPhase.value) {
    case "loading": return <p class="loading">Loading…</p>;
    case "signedOut": return <AuthView />;
    case "signedIn": return <TripListView />;
  }
}
```
Replace `webapp/src/main.tsx`:
```tsx
import { render } from "preact";
import { App } from "./ui/App";
import "./ui/styles.css";

render(<App />, document.getElementById("app")!);
```
Create a minimal `webapp/src/ui/styles.css`:
```css
:root { font-family: -apple-system, system-ui, sans-serif; }
body { margin: 0; }
.auth, .triplist, .tripdetail { max-width: 640px; margin: 0 auto; padding: 16px; }
.auth input, .auth button { display: block; width: 100%; margin: 8px 0; padding: 10px; font-size: 16px; }
.error { color: #c00; }
.link { background: none; border: none; color: #06c; cursor: pointer; }
.tabs { display: flex; gap: 8px; margin: 12px 0; }
.tabs button[aria-selected="true"] { font-weight: 700; }
.done { text-decoration: line-through; opacity: .6; }
```

- [ ] **Step 3: Build (TripListView created in Task 4 — this step builds after Task 4; for now stub it)**

To keep Task 3 self-contained, create a temporary stub `webapp/src/ui/TripListView.tsx`:
```tsx
export function TripListView() { return <main class="triplist"><h1>Trips</h1></main>; }
```
Then:
```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm run build && npm test
```
Expected: build succeeds; 42 tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/ui/AuthView.tsx webapp/src/ui/App.tsx webapp/src/ui/TripListView.tsx webapp/src/ui/styles.css webapp/src/main.tsx
git commit -m "feat(web): auth view + root gating"
```

---

### Task 4: Trip list + create

**Files:**
- Modify: `webapp/src/ui/TripListView.tsx`

- [ ] **Step 1: Replace the stub with the real list**

Replace `webapp/src/ui/TripListView.tsx`:
```tsx
import { useState } from "preact/hooks";
import { trips, tripActions, authActions } from "./store";
import { TripDetailView } from "./TripDetailView";

export function TripListView() {
  const [openId, setOpenId] = useState<string | null>(null);
  const [name, setName] = useState("");

  if (openId) return <TripDetailView tripId={openId} onBack={() => setOpenId(null)} />;

  return (
    <main class="triplist">
      <header><h1>Trips</h1><button class="link" onClick={() => void authActions.signOut()}>Sign out</button></header>
      <ul>
        {trips.value.map((t) => (
          <li key={t.id}>
            <button class="link" onClick={() => setOpenId(t.id)}>
              {t.name || "(untitled)"} — {t.items.filter((i) => i.isDone).length}/{t.items.length}
            </button>
          </li>
        ))}
      </ul>
      <form onSubmit={(e) => { e.preventDefault(); if (name.trim()) { tripActions.create(name.trim(), 0, 0); setName(""); } }}>
        <input placeholder="New trip name" value={name}
               onInput={(e) => setName((e.target as HTMLInputElement).value)} />
        <button type="submit">Add Trip</button>
      </form>
    </main>
  );
}
```

- [ ] **Step 2: Build (TripDetailView created in Task 5; stub it)**

Create stub `webapp/src/ui/TripDetailView.tsx`:
```tsx
export function TripDetailView({ onBack }: { tripId: string; onBack: () => void }) {
  return <main class="tripdetail"><button class="link" onClick={onBack}>← Back</button></main>;
}
```
```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm run build && npm test
```
Expected: build succeeds; 42 tests pass.

- [ ] **Step 3: Commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/src/ui/TripListView.tsx webapp/src/ui/TripDetailView.tsx
git commit -m "feat(web): trip list + create"
```

---

### Task 5: Trip detail (prep / itinerary / packing)

**Files:**
- Modify: `webapp/src/ui/TripDetailView.tsx`

- [ ] **Step 1: Replace the stub with tabbed checklists**

Replace `webapp/src/ui/TripDetailView.tsx`:
```tsx
import { useState } from "preact/hooks";
import { trips, tripActions } from "./store";
import type { ItemKind } from "../model/trip";

const TABS: { id: ItemKind | "itinerary"; label: string; kinds: ItemKind[] }[] = [
  { id: "prep", label: "Prep", kinds: ["prep", "hotel", "doc"] },
  { id: "itinerary", label: "Itinerary", kinds: ["itinerary"] },
  { id: "packing", label: "Packing", kinds: ["packing"] },
];

export function TripDetailView({ tripId, onBack }: { tripId: string; onBack: () => void }) {
  const [tab, setTab] = useState(0);
  const [label, setLabel] = useState("");
  const trip = trips.value.find((t) => t.id === tripId);
  if (!trip) return <main class="tripdetail"><button class="link" onClick={onBack}>← Back</button><p>Trip not found</p></main>;

  const active = TABS[tab];
  const items = trip.items.filter((i) => active.kinds.includes(i.kind));
  const addKind: ItemKind = active.id === "itinerary" ? "itinerary" : active.id === "packing" ? "packing" : "prep";

  return (
    <main class="tripdetail">
      <button class="link" onClick={onBack}>← Back</button>
      <h1>{trip.name}</h1>
      <nav class="tabs">
        {TABS.map((t, i) => (
          <button key={t.id} aria-selected={i === tab} onClick={() => setTab(i)}>{t.label}</button>
        ))}
      </nav>
      <ul>
        {items.map((it) => (
          <li key={it.id}>
            <label class={it.isDone ? "done" : ""}>
              <input type="checkbox" checked={it.isDone}
                     onChange={() => tripActions.toggleItem(tripId, it.id)} />
              {it.label}
            </label>
          </li>
        ))}
      </ul>
      <form onSubmit={(e) => { e.preventDefault(); if (label.trim()) { tripActions.addItem(tripId, addKind, label.trim()); setLabel(""); } }}>
        <input placeholder={`Add to ${active.label}`} value={label}
               onInput={(e) => setLabel((e.target as HTMLInputElement).value)} />
        <button type="submit">Add</button>
      </form>
    </main>
  );
}
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
git add webapp/src/ui/TripDetailView.tsx
git commit -m "feat(web): trip detail with prep/itinerary/packing"
```

---

### Task 6: PWA — manifest + service worker

**Files:**
- Create: `webapp/public/manifest.webmanifest`, `webapp/public/sw.js`
- Modify: `webapp/index.html`, `webapp/src/main.tsx`

- [ ] **Step 1: Manifest + icons**

Create `webapp/public/manifest.webmanifest`:
```json
{
  "name": "WanderIQ",
  "short_name": "WanderIQ",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#0a84ff",
  "icons": [
    { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```
Copy the existing PWA icons (reuse v1's) into `webapp/public/`:
```bash
cp trip-webapp/icon-192.png trip-webapp/icon-512.png webapp/public/
```

- [ ] **Step 2: Service worker (cache-first app shell)**

Create `webapp/public/sw.js`:
```js
// Minimal app-shell cache. Data is offline-first via IndexedDB (the sync engine),
// so the SW only needs to serve the built shell when offline.
const CACHE = "wanderiq-shell-v1";
self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(["/", "/index.html"])));
  self.skipWaiting();
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((ks) =>
    Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))));
});
self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  // Never cache Supabase API/Realtime; network-only.
  if (url.hostname.endsWith("supabase.co")) return;
  e.respondWith(caches.match(e.request).then((r) => r ?? fetch(e.request)));
});
```

- [ ] **Step 3: Link manifest + register SW**

In `webapp/index.html` `<head>` add:
```html
    <link rel="manifest" href="/manifest.webmanifest" />
    <meta name="theme-color" content="#0a84ff" />
```
At the end of `webapp/src/main.tsx` add:
```tsx
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => navigator.serviceWorker.register("/sw.js"));
}
```

- [ ] **Step 4: Build + commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
npm run build
ls dist/manifest.webmanifest dist/sw.js dist/icon-192.png   # Vite copies public/ to dist/
cd /Users/wyu610/_Dev/WanderIQ
git add webapp/public webapp/index.html webapp/src/main.tsx
git commit -m "feat(web): PWA manifest + app-shell service worker"
```

---

### Task 7: Browser end-to-end verification (USER-assisted)

**Files:** none

Requires a real `webapp/.env` (anon key + URL) and the dev project with "Confirm
email" OFF. This is the first true live run of the web app.

- [ ] **Step 1: Run the dev server**

```bash
cd /Users/wyu610/_Dev/WanderIQ/webapp
# Put real values in .env first (VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY)
npm run dev
```
Note the local URL (e.g. http://localhost:5173).

- [ ] **Step 2: Playwright headless smoke (signed-out)**

Use the Playwright MCP to navigate to the dev URL and assert the auth screen
renders (the "WanderIQ" heading + email/password fields + Sign in with Apple).
This confirms the built app loads, Preact renders, and the auth gate resolves to
signedOut without a session — no credentials needed.

- [ ] **Step 3: Signed-in run (manual or Playwright with a test account)**

Sign up/in with email, create a trip, add + check an item. Confirm:
- the item persists across a reload (IndexedDB),
- a `trip_items` row appears server-side:
  `psql "$SUPABASE_DB_URL" -tAc "select count(*) from trip_items where is_done"`,
- if signed in on a second browser/device as the same user, the trip appears
  (pull) and edits propagate within seconds (Realtime).

- [ ] **Step 4: Record results**

No commit needed; report what passed. Any defect found here is a real
integration bug to fix (the UI/coordinator/backend were build-verified, not
runtime-verified before this).

---

## Done criteria

- `cd webapp && npm test` (42) and `npm run build` pass; `npm run preview` serves
  a working PWA shell.
- Signed-out renders `AuthView`; signed-in renders the trip list/detail; edits
  flow trip→coordinator→Supabase and back via Realtime (Task 7).
- Installable PWA (manifest + SW).
- `trip-webapp/` (v1) still untouched.
- **This completes sub-project 4** (the web client). Next: **sub-project 5 —
  sharing** (per-trip email invites + roles + invite Edge Function, restoring the
  sharing removed in iOS 3c), then **6 — import/export** (JSON + CSV).

## Notes / risks

- UI is functional-first; styling/bilingual parity with the old PWA is a
  follow-up, not a blocker.
- Task 7 is where the whole web stack (and, with auth, the broader v2) is first
  exercised live — budget for small integration fixes (e.g. the iOS-3a date
  format reconcile, RLS edge cases, Realtime filter scoping).
- Deployment (Vercel/Netlify static host) is a separate, simple step once Task 7
  passes — the build output in `dist/` is a static PWA.
