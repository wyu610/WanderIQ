# WanderIQ v2 — Sub-project 6c: iOS Import/Export UI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the 6a Swift codec into the iOS UI — export the open trip as JSON or CSV via the system save sheet, and import a JSON/CSV file as a new trip.

**Architecture:** A tiny `FileDocument` (`TripExportDocument`) wraps the codec's bytes for SwiftUI's `.fileExporter`. `TripDetailView` gets an Export menu (JSON / CSV) that builds the document from `TripExportCodec.export{JSON,CSV}` for the viewed trip. `TripListView` gets an Import button using `.fileImporter`; the picked file is decoded by `TripExportCodec` and added via `model.addTrip(...)` — which already fires `store.onChange` → persistence **and** sync capture, so imported trips sync like any other. **Import creates a NEW trip** (matches the format's fresh-id import; JSON yields a full trip, CSV yields a new trip whose items/days come from the rows). Build-verified; the actual document picker is a user runtime check.

**Why import = new trip:** `AppModel`/`TripStore` expose `addTrip` + per-item intents but no whole-trip *replace* or day-management intent. Creating a new trip on import uses the existing synced `addTrip` path with zero new Kit surface. "Merge CSV into the open trip" is a sensible later refinement (needs a `replaceTrip`/day API).

**Tech Stack:** SwiftUI `.fileExporter`/`.fileImporter`, `UniformTypeIdentifiers`, XcodeGen. `TripExportCodec` is `public` in WanderIQKit (already a dependency).

**Spec:** design §9.2. Web equivalent = 6d.

**Verification:** package `cd WanderIQKit && make test` (unchanged, 74 — no Kit change); app `xcodegen generate && xcodebuild … build`. Picker runtime = user.

---

### Task 1: TripExportDocument + Export menu in TripDetailView

**Files:**
- Create: `WanderIQ/Features/ImportExport/TripExportDocument.swift`
- Modify: `WanderIQ/Features/TripDetail/TripDetailView.swift`

- [ ] **Step 1: Write the FileDocument**

Create `WanderIQ/Features/ImportExport/TripExportDocument.swift`:
```swift
import SwiftUI
import UniformTypeIdentifiers

/// Minimal document wrapper so SwiftUI's `.fileExporter` can write the codec's
/// bytes (JSON or CSV). Read support is unused (import uses `.fileImporter`).
struct TripExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
```

- [ ] **Step 2: Add the Export menu to TripDetailView**

In `WanderIQ/Features/TripDetail/TripDetailView.swift`, add export state and a
toolbar Export menu + `.fileExporter`. Add `import UniformTypeIdentifiers` at the
top. Add these `@State`s to the struct (next to `showingShare`):
```swift
    @State private var exportDoc: TripExportDocument?
    @State private var exportType: UTType = .json
    @State private var exportName = "trip"
    @State private var showingExporter = false
```
Replace the existing `.toolbar { … }` block with one that has BOTH an Export menu
and the existing Share button:
```swift
            .toolbar {
                Menu {
                    Button("Export JSON") { startExport(.json, trip: trip) }
                    Button("Export CSV") { startExport(.commaSeparatedText, trip: trip) }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export Trip")
                Button { showingShare = true } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
                .accessibilityLabel("Share Trip")
            }
            .fileExporter(isPresented: $showingExporter, document: exportDoc,
                          contentType: exportType, defaultFilename: exportName) { _ in }
            .sheet(isPresented: $showingShare) { ShareView(tripID: tripID) }
```
And add this private method to the struct (the system appends the right extension
from `contentType`, so `defaultFilename` carries no extension):
```swift
    private func startExport(_ type: UTType, trip: Trip) {
        guard let data = type == .commaSeparatedText
            ? Data(TripExportCodec.exportCSV(trip).utf8)
            : try? TripExportCodec.exportJSON(trip) else { return }
        exportDoc = TripExportDocument(data: data)
        exportType = type
        exportName = trip.name.isEmpty ? "trip" : trip.name
        showingExporter = true
    }
```

- [ ] **Step 3: Build + commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)|error:' | head -8
git add WanderIQ/Features/ImportExport/TripExportDocument.swift WanderIQ/Features/TripDetail/TripDetailView.swift
git commit -m "feat(ios): export trip as JSON/CSV via fileExporter"
```
Expected: `** BUILD SUCCEEDED **`. If `TripExportCodec` is not found, confirm
`import WanderIQKit` is present (it is) and report (BLOCKED).

---

### Task 2: Import a file as a new trip in TripListView

**Files:**
- Modify: `WanderIQ/Features/TripList/TripListView.swift`

- [ ] **Step 1: Add the Import button + importer**

In `WanderIQ/Features/TripList/TripListView.swift`, add `import UniformTypeIdentifiers`
at the top, add `@State private var showingImporter = false` to `TripListView`, add an
Import toolbar button before the existing `+` button, attach `.fileImporter`, and add
the handler. Replace the `.toolbar { … }` block with:
```swift
            .toolbar {
                Button { showingImporter = true } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("Import Trip")
                Button { showingNewTrip = true } label: {
                    Image(systemName: "plus")
                }
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.json, .commaSeparatedText, .plainText, .text]) { result in
                importTrip(result)
            }
```
(Leave the existing `.sheet(isPresented: $showingNewTrip) { NewTripView() }` as-is.)
Add this private method to `TripListView`:
```swift
    private func importTrip(_ result: Result<URL, Error>) {
        guard case .success(let url) = result,
              url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        if url.pathExtension.lowercased() == "csv" {
            var trip = Trip(name: url.deletingPathExtension().lastPathComponent,
                            startDate: Date(timeIntervalSince1970: 0),
                            endDate: Date(timeIntervalSince1970: 0))
            TripExportCodec.importCSVItems(String(decoding: data, as: UTF8.self), into: &trip)
            model.addTrip(trip)
        } else if let trip = try? TripExportCodec.importJSON(data) {
            model.addTrip(trip)
        }
    }
```

- [ ] **Step 2: Build + commit**

```bash
cd /Users/wyu610/_Dev/WanderIQ
xcodegen generate
xcodebuild -project WanderIQ.xcodeproj -scheme WanderIQ -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E 'BUILD (SUCCEEDED|FAILED)|error:' | head -8
git add WanderIQ/Features/TripList/TripListView.swift
git commit -m "feat(ios): import JSON/CSV file as a new trip"
```
Expected: `** BUILD SUCCEEDED **`.

---

### Task 3: Runtime verification (USER — device/simulator picker)

**Files:** none

- [ ] In the running app: open a trip → Export menu → Export JSON → save to Files.
  Then Trips list → Import → pick that file → a new trip appears with the same
  contents. Repeat with CSV (export → reimport adds a trip whose items came from
  the rows). Confirm imported trips sync (appear after a pull / on the other client
  once auth is verified). Report any picker/decoding issues (no commit).

---

## Done criteria

- App builds; Export menu on a trip writes JSON & CSV via the save sheet; Import on
  the list reads a JSON/CSV file into a new (synced) trip.
- Package tests unchanged (74) — no Kit change.
- Picker runtime verified by the user (Task 3).
- Only **6d** (web import/export UI) remains; after it, v2 feature scope is complete.

## Notes for 6d / later

- 6d mirrors this in Preact: export = `new Blob([text], { type })` + an `<a download>`;
  import = a hidden `<input type="file">` → read text → `importJSON`/`importCSVItems`
  → create via the `tripActions` path so it enters the outbox.
- Follow-up: "merge CSV into the open trip" needs an `AppModel.replaceTrip` (and a
  day-management intent) so imported rows can append to an existing trip instead of
  creating a new one.
