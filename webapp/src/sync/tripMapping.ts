import { newTrip, type ChecklistItem, type ItemKind, type Place, type Trip, type TripDay } from "../model/trip";
import type { EntityKind, SyncRecord } from "./types";

const SEP = "\u{1f}";
const num = (s: string | undefined, d = 0): number => (s !== undefined && s !== "" ? Number(s) : d);

/** Apply a non-deleted record into the trips map (shell-creating its trip). */
export function applyRecord(rec: SyncRecord, trips: Map<string, Trip>): void {
  let trip = trips.get(rec.tripId);
  if (!trip) {
    trip = newTrip({ id: rec.tripId, name: "" });
    trips.set(rec.tripId, trip);
  }
  const f = rec.fields ?? {};
  if (rec.kind === "trip" && rec.id === trip.id) {
    if (f.name !== undefined) trip.name = f.name;
    if (f.startDate !== undefined) trip.startDate = num(f.startDate);
    if (f.endDate !== undefined) trip.endDate = num(f.endDate);
    if (f.destinations !== undefined) trip.destinations = f.destinations === "" ? [] : f.destinations.split(SEP);
    if (f.schemaVersion !== undefined) trip.schemaVersion = num(f.schemaVersion, 1);
    trip.modifiedAt = rec.modifiedAt;
  } else if (rec.kind === "day") {
    const day: TripDay = { id: rec.id, date: num(f.date), city: f.city ?? "",
      title: f.title ?? "", modifiedAt: rec.modifiedAt };
    upsertById(trip.days, day);
  } else if (rec.kind === "item") {
    let place: Place | undefined;
    if (f.placeName !== undefined) {
      place = { name: f.placeName, query: f.placeQuery ?? "",
        latitude: f.placeLat !== undefined ? Number(f.placeLat) : undefined,
        longitude: f.placeLon !== undefined ? Number(f.placeLon) : undefined };
    }
    const item: ChecklistItem = {
      id: rec.id, kind: (f.kind as ItemKind) ?? "prep", label: f.label ?? "",
      notes: f.notes ?? "", dayId: f.dayID, time: f.time, owner: f.owner,
      isDone: f.isDone === "true", sortOrder: num(f.sortOrder),
      reminderDate: f.reminderDate !== undefined ? num(f.reminderDate) : undefined,
      place, modifiedAt: rec.modifiedAt };
    upsertById(trip.items, item);
  }
}

/** Build wire fields for an entity from a trip (push side). */
export function recordFields(kind: EntityKind, id: string, trips: Map<string, Trip>): Record<string, string> {
  const trip = kind === "trip" ? trips.get(id) : [...trips.values()].find((t) => containsEntity(t, kind, id));
  if (!trip) return {};
  if (kind === "trip") {
    return { name: trip.name, startDate: String(trip.startDate), endDate: String(trip.endDate),
      destinations: trip.destinations.join(SEP), schemaVersion: String(trip.schemaVersion) };
  }
  if (kind === "day") {
    const d = trip.days.find((x) => x.id === id);
    return d ? { date: String(d.date), city: d.city, title: d.title } : {};
  }
  const it = trip.items.find((x) => x.id === id);
  if (!it) return {};
  const f: Record<string, string> = { kind: it.kind, label: it.label, notes: it.notes,
    isDone: it.isDone ? "true" : "false", sortOrder: String(it.sortOrder) };
  if (it.dayId !== undefined) f.dayID = it.dayId;
  if (it.time !== undefined) f.time = it.time;
  if (it.owner !== undefined) f.owner = it.owner;
  if (it.reminderDate !== undefined) f.reminderDate = String(it.reminderDate);
  if (it.place) {
    f.placeName = it.place.name; f.placeQuery = it.place.query;
    if (it.place.latitude !== undefined) f.placeLat = String(it.place.latitude);
    if (it.place.longitude !== undefined) f.placeLon = String(it.place.longitude);
  }
  return f;
}

function upsertById<T extends { id: string }>(arr: T[], v: T): void {
  const i = arr.findIndex((x) => x.id === v.id);
  if (i >= 0) arr[i] = v; else arr.push(v);
}
function containsEntity(t: Trip, kind: EntityKind, id: string): boolean {
  return kind === "day" ? t.days.some((d) => d.id === id) : t.items.some((it) => it.id === id);
}
