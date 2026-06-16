import { useState } from "preact/hooks";
import { tripActions } from "./store";
import { mapsUrl } from "./mapsLink";
import type { ChecklistItem, ItemKind, Place, Trip } from "../model/trip";

interface Props {
  tripId: string;
  trip: Trip;
  item?: ChecklistItem;
  kind: ItemKind;
  initialDayId?: string; // preset day for a NEW itinerary item added from a day section
  onClose: () => void;
}

/** epoch seconds → "YYYY-MM-DDTHH:mm" in LOCAL time for <input type=datetime-local>. */
function toLocalInput(sec: number): string {
  const d = new Date(sec * 1000);
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
}

export function ItemEditor({ tripId, trip, item, kind, initialDayId, onClose }: Props) {
  const [label, setLabel] = useState(item?.label ?? "");
  const [notes, setNotes] = useState(item?.notes ?? "");
  const [owner, setOwner] = useState(item?.owner ?? "");
  const [dayId, setDayId] = useState(item?.dayId ?? initialDayId ?? "");
  const [time, setTime] = useState(item?.time ?? "");
  // datetime-local shows LOCAL wall-clock; save (Date.parse below) also reads it
  // as local, so load must convert the stored epoch to local — not UTC — or a
  // round-trip would shift the reminder by the timezone offset.
  const [reminder, setReminder] = useState(
    item?.reminderDate ? toLocalInput(item.reminderDate) : ""
  );
  const [placeName, setPlaceName] = useState(item?.place?.name ?? "");
  const [placeQuery, setPlaceQuery] = useState(item?.place?.query ?? "");

  const showOwner = kind !== "doc" && kind !== "hotel";
  const showDayTime = kind === "itinerary";
  const showPlace = kind === "itinerary" || kind === "prep" || kind === "hotel";

  const currentPlace: Place | undefined =
    showPlace && placeName.trim()
      ? { name: placeName.trim(), query: placeQuery.trim() }
      : undefined;

  function handleSave(e: Event) {
    e.preventDefault();
    if (!label.trim()) return;
    const saved: ChecklistItem = {
      id: item?.id ?? crypto.randomUUID(),
      kind,
      label: label.trim(),
      notes: notes.trim(),
      isDone: item?.isDone ?? false,
      sortOrder: item?.sortOrder ?? 0,
      modifiedAt: Math.floor(Date.now() / 1000),
      owner: showOwner && owner.trim() ? owner.trim() : undefined,
      dayId: showDayTime && dayId ? dayId : undefined,
      time: showDayTime && time ? time : undefined,
      reminderDate: reminder ? Math.floor(Date.parse(reminder) / 1000) : undefined,
      place: currentPlace,
    };
    tripActions.upsertItem(tripId, saved);
    onClose();
  }

  function handleDelete() {
    if (item) {
      tripActions.deleteItem(tripId, item.id);
      onClose();
    }
  }

  return (
    <div class="editor">
      <div class="editor-header">
        <button class="link" onClick={onClose}>← Cancel</button>
        <strong>{item ? "Edit Item" : "New Item"}</strong>
        {item && <button class="link danger" onClick={handleDelete}>Delete</button>}
      </div>
      <form onSubmit={handleSave} class="editor-form">
        <label>
          Name
          <input value={label} required onInput={(e) => setLabel((e.target as HTMLInputElement).value)} />
        </label>
        <label>
          Notes
          <textarea value={notes} rows={3} onInput={(e) => setNotes((e.target as HTMLTextAreaElement).value)} />
        </label>
        {showOwner && (
          <label>
            Owner
            <input value={owner} onInput={(e) => setOwner((e.target as HTMLInputElement).value)} />
          </label>
        )}
        {showDayTime && (
          <>
            <label>
              Day
              <select value={dayId} onChange={(e) => setDayId((e.target as HTMLSelectElement).value)}>
                <option value="">— no day —</option>
                {trip.days.map((d) => (
                  <option key={d.id} value={d.id}>
                    {new Date(d.date * 1000).toLocaleDateString()}{d.title ? ` — ${d.title}` : ""}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Time
              <input type="time" value={time} onInput={(e) => setTime((e.target as HTMLInputElement).value)} />
            </label>
          </>
        )}
        <label>
          Reminder
          <input
            type="datetime-local"
            value={reminder}
            onInput={(e) => setReminder((e.target as HTMLInputElement).value)}
          />
        </label>
        <p class="muted hint">Reminders are delivered by the WanderIQ iOS app.</p>
        {showPlace && (
          <fieldset>
            <legend>Place</legend>
            <label>
              Place name
              <input value={placeName} onInput={(e) => setPlaceName((e.target as HTMLInputElement).value)} />
            </label>
            <label>
              Search text
              <input value={placeQuery} onInput={(e) => setPlaceQuery((e.target as HTMLInputElement).value)} />
            </label>
            {currentPlace && (
              <a href={mapsUrl(currentPlace)} target="_blank" rel="noopener" class="maps-link">
                Open in Maps
              </a>
            )}
          </fieldset>
        )}
        <div class="editor-actions">
          <button type="submit">Save</button>
        </div>
      </form>
    </div>
  );
}
