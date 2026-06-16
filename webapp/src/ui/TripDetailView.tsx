import { useState } from "preact/hooks";
import { trips, tripActions } from "./store";
import type { ChecklistItem, ItemKind } from "../model/trip";
import { ShareView } from "./ShareView";
import { ItemEditor } from "./ItemEditor";
import { mapsUrl } from "./mapsLink";
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
  const [editing, setEditing] = useState<{ item?: ChecklistItem } | null>(null);
  const trip = trips.value.find((t) => t.id === tripId);
  if (!trip) return <main class="tripdetail"><button class="link" onClick={onBack}>← Back</button><p>Trip not found</p></main>;

  if (sharing) return (
    <main class="tripdetail">
      <ShareView tripId={tripId} onClose={() => setSharing(false)} />
    </main>
  );

  const active = TABS[tab];
  const addKind: ItemKind = active.id === "itinerary" ? "itinerary" : active.id === "packing" ? "packing" : "prep";

  if (editing) return (
    <main class="tripdetail">
      <ItemEditor
        tripId={tripId}
        trip={trip}
        item={editing.item}
        kind={editing.item?.kind ?? addKind}
        onClose={() => setEditing(null)}
      />
    </main>
  );

  const items = trip.items.filter((i) => active.kinds.includes(i.kind));

  // For the Itinerary tab, build day-grouped view
  let itemsContent;
  if (active.id === "itinerary") {
    const byDay = new Map<string, ChecklistItem[]>();
    const unscheduled: ChecklistItem[] = [];
    for (const it of items) {
      if (it.dayId) {
        const arr = byDay.get(it.dayId) ?? [];
        arr.push(it);
        byDay.set(it.dayId, arr);
      } else {
        unscheduled.push(it);
      }
    }
    const sortByTime = (a: ChecklistItem, b: ChecklistItem) =>
      (a.time ?? "").localeCompare(b.time ?? "");

    itemsContent = (
      <div>
        {trip.days.map((d) => {
          const dayItems = (byDay.get(d.id) ?? []).slice().sort(sortByTime);
          return (
            <div key={d.id} class="itinerary-day">
              <h3>
                {new Date(d.date * 1000).toLocaleDateString()}
                {d.title ? ` — ${d.title}` : ""}
              </h3>
              <ul>
                {dayItems.map((it) => (
                  <li key={it.id}>
                    <label class={it.isDone ? "done" : ""}>
                      <input type="checkbox" checked={it.isDone}
                             onChange={() => tripActions.toggleItem(tripId, it.id)} />
                      <span class="item-label" onClick={() => setEditing({ item: it })}>{it.label}</span>
                    </label>
                    <div class="item-detail">
                      {it.time && <span>{it.time}</span>}
                      {it.owner && <span> · {it.owner}</span>}
                      {it.place && (
                        <> · <a href={mapsUrl(it.place)} target="_blank" rel="noopener">Open in Maps</a></>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            </div>
          );
        })}
        {unscheduled.length > 0 && (
          <div class="itinerary-day">
            <h3>Unscheduled</h3>
            <ul>
              {unscheduled.slice().sort(sortByTime).map((it) => (
                <li key={it.id}>
                  <label class={it.isDone ? "done" : ""}>
                    <input type="checkbox" checked={it.isDone}
                           onChange={() => tripActions.toggleItem(tripId, it.id)} />
                    <span class="item-label" onClick={() => setEditing({ item: it })}>{it.label}</span>
                  </label>
                  <div class="item-detail">
                    {it.owner && <span>{it.owner}</span>}
                    {it.place && (
                      <> · <a href={mapsUrl(it.place)} target="_blank" rel="noopener">Open in Maps</a></>
                    )}
                  </div>
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>
    );
  } else {
    itemsContent = (
      <ul>
        {items.map((it) => (
          <li key={it.id}>
            <label class={it.isDone ? "done" : ""}>
              <input type="checkbox" checked={it.isDone}
                     onChange={() => tripActions.toggleItem(tripId, it.id)} />
              <span class="item-label" onClick={() => setEditing({ item: it })}>{it.label}</span>
            </label>
            <div class="item-detail">
              {it.time && <span>{it.time}</span>}
              {it.owner && <span>{it.time ? " · " : ""}{it.owner}</span>}
              {it.place && (
                <> {(it.time || it.owner) ? " · " : ""}<a href={mapsUrl(it.place)} target="_blank" rel="noopener">Open in Maps</a></>
              )}
            </div>
          </li>
        ))}
      </ul>
    );
  }

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
      {itemsContent}
      <form onSubmit={(e) => { e.preventDefault(); if (label.trim()) { tripActions.addItem(tripId, addKind, label.trim()); setLabel(""); } }}>
        <input placeholder={`Add to ${active.label}`} value={label}
               onInput={(e) => setLabel((e.target as HTMLInputElement).value)} />
        <button type="submit">Add</button>
        <button type="button" class="link" onClick={() => setEditing({})}>＋ details</button>
      </form>
    </main>
  );
}
