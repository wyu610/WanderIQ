import type { Trip, TripDay, ChecklistItem, ItemKind, Place } from "../model/trip";

// ── date helpers ───────────────────────────────────────────────
// trip/day dates: epoch-seconds ↔ "YYYY-MM-DD" (UTC date-only).
const epochToDateOnly = (sec: number): string => new Date(sec * 1000).toISOString().slice(0, 10);
const dateOnlyToEpoch = (s: string): number => Math.floor(Date.parse(`${s}T00:00:00Z`) / 1000);
// reminderDate: epoch-seconds ↔ ISO-8601 WITHOUT millis (matches Swift ISO8601DateFormatter).
const epochToIso = (sec: number): string => new Date(sec * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");
const isoToEpoch = (s: string): number => Math.floor(Date.parse(s) / 1000);

// ── wire DTOs (canonical JSON shape) ───────────────────────────
interface PlaceDTO { name: string; query: string; latitude: number | null; longitude: number | null; }
interface DayDTO { date: string; city: string; title: string; }
interface ItemDTO {
  kind: string; label: string; notes: string; dayIndex: number | null; time: string | null;
  owner: string | null; isDone: boolean; sortOrder: number; reminderDate: string | null; place: PlaceDTO | null;
}
interface TripDTO {
  schemaVersion: number; name: string; startDate: string; endDate: string;
  destinations: string[]; days: DayDTO[]; items: ItemDTO[];
}

// ── JSON ───────────────────────────────────────────────────────
export function exportJSON(trip: Trip): string {
  const dayIndex = new Map(trip.days.map((d, i) => [d.id, i]));
  const dto: TripDTO = {
    schemaVersion: 1,
    name: trip.name,
    startDate: epochToDateOnly(trip.startDate),
    endDate: epochToDateOnly(trip.endDate),
    destinations: trip.destinations,
    days: trip.days.map((d) => ({ date: epochToDateOnly(d.date), city: d.city, title: d.title })),
    items: trip.items.map((it) => ({
      kind: it.kind,
      label: it.label,
      notes: it.notes,
      dayIndex: it.dayId !== undefined ? (dayIndex.get(it.dayId) ?? null) : null,
      time: it.time ?? null,
      owner: it.owner ?? null,
      isDone: it.isDone,
      sortOrder: it.sortOrder,
      reminderDate: it.reminderDate !== undefined ? epochToIso(it.reminderDate) : null,
      place: it.place
        ? { name: it.place.name, query: it.place.query,
            latitude: it.place.latitude ?? null, longitude: it.place.longitude ?? null }
        : null,
    })),
  };
  return JSON.stringify(dto, null, 2);
}

/** Parse a canonical export into a fresh-id Trip (tolerates absent or null optionals). */
export function importJSON(text: string): Trip {
  const dto = JSON.parse(text) as TripDTO;
  const now = Math.floor(Date.now() / 1000);
  const days: TripDay[] = (dto.days ?? []).map((d) => ({
    id: crypto.randomUUID(), date: dateOnlyToEpoch(d.date), city: d.city, title: d.title, modifiedAt: now,
  }));
  const items: ChecklistItem[] = (dto.items ?? []).map((i) => {
    const di = i.dayIndex;
    const dayId = di != null && di >= 0 && di < days.length ? days[di].id : undefined;
    const place: Place | undefined = i.place
      ? { name: i.place.name, query: i.place.query,
          latitude: i.place.latitude ?? undefined, longitude: i.place.longitude ?? undefined }
      : undefined;
    return {
      id: crypto.randomUUID(),
      kind: i.kind as ItemKind,
      label: i.label,
      notes: i.notes ?? "",
      dayId,
      time: i.time ?? undefined,
      owner: i.owner ?? undefined,
      isDone: i.isDone ?? false,
      sortOrder: i.sortOrder ?? 0,
      reminderDate: i.reminderDate != null ? isoToEpoch(i.reminderDate) : undefined,
      place,
      modifiedAt: now,
    };
  });
  return {
    id: crypto.randomUUID(),
    name: dto.name,
    startDate: dateOnlyToEpoch(dto.startDate),
    endDate: dateOnlyToEpoch(dto.endDate),
    destinations: dto.destinations ?? [],
    days, items, schemaVersion: 1, modifiedAt: now,
  };
}

// ── CSV (flat item-level, UTF-8 BOM) ───────────────────────────
const CSV_HEADER = "kind,label,notes,day_date,time,owner,is_done,place_name,place_query";

export function exportCSV(trip: Trip): string {
  const dayDate = new Map(trip.days.map((d) => [d.id, epochToDateOnly(d.date)]));
  const lines = [CSV_HEADER];
  for (const it of trip.items) {
    const cols = [
      it.kind, it.label, it.notes,
      it.dayId !== undefined ? (dayDate.get(it.dayId) ?? "") : "",
      it.time ?? "", it.owner ?? "", it.isDone ? "true" : "false",
      it.place?.name ?? "", it.place?.query ?? "",
    ];
    lines.push(cols.map(csvField).join(","));
  }
  return `﻿${lines.join("\n")}\n`;
}

/** Append CSV rows as items to a copy of `trip`, matching/creating a day by date. */
export function importCSVItems(csv: string, trip: Trip): Trip {
  const body = csv.startsWith("﻿") ? csv.slice(1) : csv;
  const rows = parseCSV(body);
  if (rows.length <= 1) return trip;
  const now = Math.floor(Date.now() / 1000);
  const byDate = new Map(trip.days.map((d) => [epochToDateOnly(d.date), d.id]));
  const days = [...trip.days];
  const items = [...trip.items];
  for (const row of rows.slice(1)) {
    if (row.length < 9) continue;
    let dayId: string | undefined;
    const d = row[3];
    if (d) {
      const existing = byDate.get(d);
      if (existing) dayId = existing;
      else {
        const id = crypto.randomUUID();
        days.push({ id, date: dateOnlyToEpoch(d), city: "", title: "", modifiedAt: now });
        byDate.set(d, id);
        dayId = id;
      }
    }
    const place: Place | undefined = row[7] ? { name: row[7], query: row[8] } : undefined;
    items.push({
      id: crypto.randomUUID(),
      kind: row[0] as ItemKind,
      label: row[1],
      notes: row[2],
      dayId,
      time: row[4] || undefined,
      owner: row[5] || undefined,
      isDone: row[6] === "true",
      sortOrder: items.length,
      place,
      modifiedAt: now,
    });
  }
  return { ...trip, days, items };
}

// RFC-4180-ish: quote fields containing comma/quote/newline; double inner quotes.
function csvField(s: string): string {
  if (!/[",\n]/.test(s)) return s;
  return `"${s.replace(/"/g, '""')}"`;
}

function parseCSV(text: string): string[][] {
  const rows: string[][] = [];
  let field = "";
  let row: string[] = [];
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else inQuotes = false;
      } else field += c;
    } else if (c === '"') inQuotes = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n") { row.push(field); rows.push(row); field = ""; row = []; }
    else if (c === "\r") { /* skip */ }
    else field += c;
  }
  if (field !== "" || row.length > 0) { row.push(field); rows.push(row); }
  return rows;
}
