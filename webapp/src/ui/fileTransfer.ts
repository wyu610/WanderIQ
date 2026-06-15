import { importJSON, importCSVItems } from "../export/tripExportCodec";
import { newTrip, type Trip } from "../model/trip";

/** Dispatch by extension: .csv → items onto a new trip; otherwise canonical JSON. */
export function tripFromImport(filename: string, text: string): Trip {
  if (filename.toLowerCase().endsWith(".csv")) {
    return importCSVItems(text, newTrip({ name: filename.replace(/\.[^.]+$/, "") }));
  }
  return importJSON(text);
}

/** Trigger a browser download of `text` as `filename`. */
export function download(filename: string, text: string, mime: string): void {
  const url = URL.createObjectURL(new Blob([text], { type: mime }));
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
