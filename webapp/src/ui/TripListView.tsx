import { useRef, useState } from "preact/hooks";
import { trips, tripActions, authActions } from "./store";
import { tripFromImport } from "./fileTransfer";
import { TripDetailView } from "./TripDetailView";

export function TripListView() {
  const [openId, setOpenId] = useState<string | null>(null);
  const [name, setName] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);

  async function onPick(e: Event): Promise<void> {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    try {
      tripActions.importTrip(tripFromImport(file.name, await file.text()));
    } catch {
      /* ignore malformed file; could surface a toast later */
    }
    input.value = "";  // allow re-importing the same file
  }

  if (openId) return <TripDetailView tripId={openId} onBack={() => setOpenId(null)} />;

  return (
    <main class="triplist">
      <header><h1>Trips</h1><button class="link" onClick={() => fileRef.current?.click()}>Import</button><button class="link" onClick={() => void authActions.signOut()}>Sign out</button><button class="link danger" onClick={() => { if (confirm("Permanently delete your account and all your trips? This can't be undone.")) void authActions.deleteAccount(); }}>Delete account</button></header>
      <input ref={fileRef} type="file" accept=".json,.csv,application/json,text/csv"
             style="display:none" onChange={(e) => void onPick(e)} />
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
