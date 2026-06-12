import SwiftUI
import MapKit
import WanderIQKit

/// Map of one itinerary day: a marker per item with resolved coordinates.
struct DayMapView: View {
    @Environment(\.dismiss) private var dismiss
    let day: TripDay
    let items: [ChecklistItem]

    private var placed: [(item: ChecklistItem, coordinate: CLLocationCoordinate2D)] {
        items.compactMap { item in
            guard let place = item.place,
                  let lat = place.latitude, let lon = place.longitude else { return nil }
            return (item, CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if placed.isEmpty {
                    ContentUnavailableView("No places on this day", systemImage: "mappin.slash",
                                           description: Text("Attach places to items to see them here."))
                } else {
                    Map {
                        ForEach(placed, id: \.item.id) { entry in
                            Marker(entry.item.label, coordinate: entry.coordinate)
                        }
                    }
                }
            }
            .navigationTitle(day.title.isEmpty ? day.city : day.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
