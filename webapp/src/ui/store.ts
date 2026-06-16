import { signal } from "@preact/signals";
import { WebAuth, type Phase } from "../auth/webAuth";
import { WebSyncCoordinator } from "../sync/webSyncCoordinator";
import { newTrip, type ChecklistItem, type ItemKind, type Trip } from "../model/trip";
import { claimInvites } from "../supabase/sharing";
import { deleteAccount as rpcDeleteAccount } from "../supabase/account";
import { IdbStore } from "../store/idbStore";

export const authPhase = signal<Phase>("loading");
export const trips = signal<Trip[]>([]);

const auth = new WebAuth();
let coordinator: WebSyncCoordinator | undefined;

auth.onChange(() => {
  authPhase.value = auth.phase;
  if (auth.isSignedIn && !coordinator) void startSync();
});

async function startSync(): Promise<void> {
  try { await claimInvites(); } catch { /* non-fatal; retried next sign-in */ }
  coordinator = new WebSyncCoordinator();
  coordinator.onChange = () => { trips.value = [...coordinator!.state.trips.values()]; };
  await coordinator.start();
  trips.value = [...coordinator.state.trips.values()];
}

/** Clear local sync state (IndexedDB) and reload to a clean signed-out app — so
 *  a shared browser shows nothing after sign-out and nothing lingers after an
 *  account is deleted. */
async function wipeLocalAndReload(): Promise<void> {
  try { await new IdbStore().clear(); } catch { /* ignore */ }
  location.reload();
}

export const authActions = {
  signIn: (e: string, p: string) => auth.signIn(e, p),
  signUp: (e: string, p: string) => auth.signUp(e, p),
  google: () => auth.signInWithGoogle(),
  apple: () => auth.signInWithApple(),
  async signOut(): Promise<void> {
    await auth.signOut();
    await wipeLocalAndReload();
  },
  async deleteAccount(): Promise<void> {
    await rpcDeleteAccount();
    await auth.signOut();
    await wipeLocalAndReload();
  },
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
  importTrip(trip: Trip): void {
    commit(trip);
  },
};
