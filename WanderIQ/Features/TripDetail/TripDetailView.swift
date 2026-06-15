import SwiftUI
import WanderIQKit

struct TripDetailView: View {
    @Environment(AppModel.self) private var model
    let tripID: UUID
    @State private var showingShare = false

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
                Button { showingShare = true } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
                .accessibilityLabel("Share Trip")
            }
            .sheet(isPresented: $showingShare) { ShareView(tripID: tripID) }
        } else {
            ContentUnavailableView("Trip not found", systemImage: "questionmark.circle")
        }
    }
}
