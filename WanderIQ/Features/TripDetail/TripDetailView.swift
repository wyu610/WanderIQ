import SwiftUI
import WanderIQKit

struct TripDetailView: View {
    @Environment(AppModel.self) private var model
    let tripID: UUID

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
        } else {
            ContentUnavailableView("Trip not found", systemImage: "questionmark.circle")
        }
    }
}
