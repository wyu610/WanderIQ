import SwiftUI
import UniformTypeIdentifiers
import WanderIQKit

struct TripDetailView: View {
    @Environment(AppModel.self) private var model
    let tripID: UUID
    @State private var showingShare = false
    @State private var exportDoc: TripExportDocument?
    @State private var exportType: UTType = .json
    @State private var exportName = "trip"
    @State private var showingExporter = false

    var body: some View {
        if let trip = model.store.trip(id: tripID) {
            TabView {
                PrepView(trip: trip)
                    .tabItem { Label("Prep", systemImage: "checklist") }
                ItineraryView(trip: trip)
                    .tabItem { Label("Itinerary", systemImage: "calendar") }
                PackingView(trip: trip)
                    .tabItem { Label("Packing", systemImage: "bag") }
            }
            .navigationTitle(trip.name)
            .navigationBarTitleDisplayMode(.inline)
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
        } else {
            ContentUnavailableView("Trip not found", systemImage: "questionmark.circle")
        }
    }

    private func startExport(_ type: UTType, trip: Trip) {
        guard let data = type == .commaSeparatedText
            ? Data(TripExportCodec.exportCSV(trip).utf8)
            : try? TripExportCodec.exportJSON(trip) else { return }
        exportDoc = TripExportDocument(data: data)
        exportType = type
        exportName = trip.name.isEmpty ? "trip" : trip.name
        showingExporter = true
    }
}
