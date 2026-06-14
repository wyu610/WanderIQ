export type ItemKind = "prep" | "hotel" | "doc" | "itinerary" | "packing";

export interface Place {
  name: string;
  query: string;
  latitude?: number;
  longitude?: number;
}

export interface ChecklistItem {
  id: string;
  kind: ItemKind;
  label: string;
  notes: string;
  dayId?: string;
  time?: string;
  owner?: string;
  isDone: boolean;
  sortOrder: number;
  reminderDate?: number; // epoch seconds
  place?: Place;
  modifiedAt: number;    // epoch seconds
}

export interface TripDay {
  id: string;
  date: number;          // epoch seconds
  city: string;
  title: string;
  modifiedAt: number;
}

export interface Trip {
  id: string;
  name: string;
  startDate: number;     // epoch seconds
  endDate: number;
  destinations: string[];
  days: TripDay[];
  items: ChecklistItem[];
  schemaVersion: number;
  modifiedAt: number;
}

export function newTrip(partial: Partial<Trip> & { name: string }): Trip {
  return {
    id: partial.id ?? crypto.randomUUID(),
    name: partial.name,
    startDate: partial.startDate ?? 0,
    endDate: partial.endDate ?? 0,
    destinations: partial.destinations ?? [],
    days: partial.days ?? [],
    items: partial.items ?? [],
    schemaVersion: partial.schemaVersion ?? 1,
    modifiedAt: partial.modifiedAt ?? 0,
  };
}
