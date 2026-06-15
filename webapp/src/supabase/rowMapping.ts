import type { EntityKind, SyncRecord } from "../sync/types";

const SEP = "\u{1f}";
const isoToEpoch = (s: string | null): number => (s ? Math.floor(Date.parse(s) / 1000) : 0);
const epochToISO = (e: number): string => new Date(e * 1000).toISOString();
// Postgres `date` columns are date-only; emit YYYY-MM-DD.
const epochToDate = (e: number): string => new Date(e * 1000).toISOString().slice(0, 10);

/** A Postgres row as returned by supabase-js (loose: columns vary by table). */
export type Row = Record<string, unknown>;

/** Pull side: Postgres row → SyncRecord (fields are epoch-number strings). */
export function rowToRecord(kind: EntityKind, row: Row): SyncRecord {
  const id = String(row.id);
  const tripId = kind === "trip" ? id : String(row.trip_id);
  const modifiedAt = isoToEpoch(row.modified_at as string | null);
  const deleted = Boolean(row.deleted);
  if (deleted) return { kind, id, tripId, modifiedAt, deleted: true };

  let fields: Record<string, string> = {};
  if (kind === "trip") {
    fields = {
      name: String(row.name ?? ""),
      startDate: String(isoToEpoch(row.start_date as string | null)),
      endDate: String(isoToEpoch(row.end_date as string | null)),
      destinations: ((row.destinations as string[] | null) ?? []).join(SEP),
      schemaVersion: String((row.schema_version as number | null) ?? 1),
    };
  } else if (kind === "day") {
    fields = {
      date: String(isoToEpoch(row.date as string | null)),
      city: String(row.city ?? ""),
      title: String(row.title ?? ""),
    };
  } else {
    fields = {
      kind: String(row.kind ?? "prep"),
      label: String(row.label ?? ""),
      notes: String(row.notes ?? ""),
      isDone: row.is_done ? "true" : "false",
      sortOrder: String((row.sort_order as number | null) ?? 0),
    };
    if (row.day_id != null) fields.dayID = String(row.day_id);
    if (row.time != null) fields.time = String(row.time);
    if (row.item_owner != null) fields.owner = String(row.item_owner);
    if (row.reminder_date != null) fields.reminderDate = String(isoToEpoch(row.reminder_date as string));
    const place = row.place as { name: string; query: string; latitude?: number; longitude?: number } | null;
    if (place) {
      fields.placeName = place.name; fields.placeQuery = place.query;
      if (place.latitude != null) fields.placeLat = String(place.latitude);
      if (place.longitude != null) fields.placeLon = String(place.longitude);
    }
  }
  return { kind, id, tripId, modifiedAt, deleted: false, fields };
}

/** Push side: SyncRecord → Postgres row. `ownerId` is injected on trip rows. */
export function recordToRow(rec: SyncRecord, ownerId: string): Row {
  const base: Row = { id: rec.id, modified_at: epochToISO(rec.modifiedAt), deleted: rec.deleted };
  if (rec.kind !== "trip") base.trip_id = rec.tripId;
  if (rec.kind === "trip") base.owner_id = ownerId;
  if (rec.deleted) return base;

  const f = rec.fields ?? {};
  const numF = (k: string): number => Number(f[k] ?? "0");
  if (rec.kind === "trip") {
    base.name = f.name ?? "";
    base.start_date = epochToDate(numF("startDate"));
    base.end_date = epochToDate(numF("endDate"));
    base.destinations = f.destinations ? f.destinations.split(SEP) : [];
    base.schema_version = Number(f.schemaVersion ?? "1");
  } else if (rec.kind === "day") {
    base.date = epochToDate(numF("date"));
    base.city = f.city ?? "";
    base.title = f.title ?? "";
  } else {
    base.kind = f.kind ?? "prep";
    base.label = f.label ?? "";
    base.notes = f.notes ?? "";
    base.is_done = f.isDone === "true";
    base.sort_order = numF("sortOrder");
    base.day_id = f.dayID ?? null;
    base.time = f.time ?? null;
    base.item_owner = f.owner ?? null;
    base.reminder_date = f.reminderDate ? epochToISO(numF("reminderDate")) : null;
    base.place = f.placeName
      ? { name: f.placeName, query: f.placeQuery ?? "",
          latitude: f.placeLat ? Number(f.placeLat) : null,
          longitude: f.placeLon ? Number(f.placeLon) : null }
      : null;
  }
  return base;
}
