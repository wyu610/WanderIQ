import { useState } from "preact/hooks";
import { trips, tripActions } from "./store";
import type { ChecklistItem, ItemKind } from "../model/trip";
import { ShareView } from "./ShareView";
import { ItemEditor } from "./ItemEditor";
import { mapsUrl } from "./mapsLink";
import { exportJSON, exportCSV } from "../export/tripExportCodec";
import { download } from "./fileTransfer";

type TabId = "prep" | "itinerary" | "packing";
const TABS: { id: TabId; label: string }[] = [
  { id: "prep", label: "Prep" },
  { id: "itinerary", label: "Itinerary" },
  { id: "packing", label: "Packing" },
];

// Prep sub-sections, mirroring the iOS PrepView (Bookings/Hotels/Documents).
const PREP_SECTIONS: { kind: ItemKind; label: string }[] = [
  { kind: "prep", label: "Bookings" },
  { kind: "hotel", label: "Hotels" },
  { kind: "doc", label: "Documents" },
];

export function TripDetailView({ tripId, onBack }: { tripId: string; onBack: () => void }) {
  const [tab, setTab] = useState<TabId>("prep");
  const [sharing, setSharing] = useState(false);
  const [editing, setEditing] = useState<{ item?: ChecklistItem; kind: ItemKind; dayId?: string } | null>(null);
  const trip = trips.value.find((t) => t.id === tripId);
  if (!trip) return <main class="tripdetail"><button class="link" onClick={onBack}>← Back</button><p>Trip not found</p></main>;

  if (sharing) return (
    <main class="tripdetail">
      <ShareView tripId={tripId} onClose={() => setSharing(false)} />
    </main>
  );

  if (editing) return (
    <main class="tripdetail">
      <ItemEditor
        tripId={tripId}
        trip={trip}
        item={editing.item}
        kind={editing.item?.kind ?? editing.kind}
        initialDayId={editing.dayId}
        onClose={() => setEditing(null)}
      />
    </main>
  );

  const byKind = (kind: ItemKind) =>
    trip.items.filter((i) => i.kind === kind).sort((a, b) => a.sortOrder - b.sortOrder);

  const row = (it: ChecklistItem) => (
    <li key={it.id}>
      <label class={it.isDone ? "done" : ""}>
        <input type="checkbox" checked={it.isDone} onChange={() => tripActions.toggleItem(tripId, it.id)} />
        <span class="item-label" onClick={() => setEditing({ item: it, kind: it.kind })}>{it.label}</span>
      </label>
      {(it.time || it.owner || it.place) && (
        <div class="item-detail">
          {[it.time, it.owner].filter(Boolean).join(" · ")}
          {it.place && (
            <>{(it.time || it.owner) ? " · " : ""}<a href={mapsUrl(it.place)} target="_blank" rel="noopener">Open in Maps</a></>
          )}
        </div>
      )}
    </li>
  );

  const section = (label: string, kind: ItemKind, list: ChecklistItem[], dayId?: string) => (
    <div class="kind-section" key={`${label}-${dayId ?? ""}`}>
      <h3>{label} <span class="muted">{list.filter((i) => i.isDone).length}/{list.length}</span></h3>
      <ul>{list.map(row)}</ul>
      <button class="link add-item" onClick={() => setEditing({ kind, dayId })}>＋ Add Item</button>
    </div>
  );

  let content;
  if (tab === "prep") {
    content = <>{PREP_SECTIONS.map((s) => section(s.label, s.kind, byKind(s.kind)))}</>;
  } else if (tab === "packing") {
    const list = byKind("packing");
    content = (
      <>
        {section("Packing", "packing", list)}
        {list.some((i) => i.isDone) && (
          <button class="link" onClick={() => tripActions.resetPacking(tripId)}>↺ Reset packing list</button>
        )}
      </>
    );
  } else {
    // Itinerary: one section per day (mirrors iOS), timed items first.
    const dayList = (dayId: string) =>
      trip.items.filter((i) => i.kind === "itinerary" && i.dayId === dayId)
        .sort((a, b) => (a.time ?? "").localeCompare(b.time ?? ""));
    const unscheduled = trip.items.filter((i) => i.kind === "itinerary" && !i.dayId)
      .sort((a, b) => (a.time ?? "").localeCompare(b.time ?? ""));
    content = (
      <>
        {trip.days.map((d) =>
          section(
            `${new Date(d.date * 1000).toLocaleDateString()}${d.title ? ` — ${d.title}` : ""}`,
            "itinerary",
            dayList(d.id),
            d.id,
          ),
        )}
        {unscheduled.length > 0 && section("Unscheduled", "itinerary", unscheduled)}
        {trip.days.length === 0 && <p class="muted">Add start and end dates to the trip to plan days.</p>}
      </>
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
        {TABS.map((t) => (
          <button key={t.id} aria-selected={t.id === tab} onClick={() => setTab(t.id)}>{t.label}</button>
        ))}
      </nav>
      {content}
    </main>
  );
}
