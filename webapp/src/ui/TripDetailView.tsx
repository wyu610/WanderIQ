import { useState } from "preact/hooks";
import { trips, tripActions } from "./store";
import type { ItemKind } from "../model/trip";
import { ShareView } from "./ShareView";
import { exportJSON, exportCSV } from "../export/tripExportCodec";
import { download } from "./fileTransfer";

const TABS: { id: ItemKind | "itinerary"; label: string; kinds: ItemKind[] }[] = [
  { id: "prep", label: "Prep", kinds: ["prep", "hotel", "doc"] },
  { id: "itinerary", label: "Itinerary", kinds: ["itinerary"] },
  { id: "packing", label: "Packing", kinds: ["packing"] },
];

export function TripDetailView({ tripId, onBack }: { tripId: string; onBack: () => void }) {
  const [tab, setTab] = useState(0);
  const [label, setLabel] = useState("");
  const [sharing, setSharing] = useState(false);
  const trip = trips.value.find((t) => t.id === tripId);
  if (!trip) return <main class="tripdetail"><button class="link" onClick={onBack}>← Back</button><p>Trip not found</p></main>;

  if (sharing) return (
    <main class="tripdetail">
      <ShareView tripId={tripId} onClose={() => setSharing(false)} />
    </main>
  );

  const active = TABS[tab];
  const items = trip.items.filter((i) => active.kinds.includes(i.kind));
  const addKind: ItemKind = active.id === "itinerary" ? "itinerary" : active.id === "packing" ? "packing" : "prep";

  return (
    <main class="tripdetail">
      <button class="link" onClick={onBack}>← Back</button>
      <button class="link" onClick={() => setSharing(true)}>Share</button>
      <button class="link" onClick={() => download(`${trip.name || "trip"}.json`, exportJSON(trip), "application/json")}>Export JSON</button>
      <button class="link" onClick={() => download(`${trip.name || "trip"}.csv`, exportCSV(trip), "text/csv")}>Export CSV</button>
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
