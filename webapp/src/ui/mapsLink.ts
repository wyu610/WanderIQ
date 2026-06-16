import type { Place } from "../model/trip";

/** Universal Google Maps search URL (opens in any browser / the Maps app). */
export function mapsUrl(place: Place): string {
  const q = place.latitude != null && place.longitude != null
    ? `${place.latitude},${place.longitude}`
    : (place.query || place.name);
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(q)}`;
}
