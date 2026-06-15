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
