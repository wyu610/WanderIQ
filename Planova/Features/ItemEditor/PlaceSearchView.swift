import SwiftUI
import MapKit
import PlanovaKit

/// MKLocalSearch-backed picker; returns a Place with resolved coordinates.
struct PlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Place) -> Void

    @State private var query = ""
    @State private var results: [MKMapItem] = []

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    ContentUnavailableView("Search for a place", systemImage: "magnifyingglass",
                                           description: Text("Type a name and press Search."))
                } else {
                    List(results, id: \.self) { item in
                        Button {
                            select(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "—").foregroundStyle(.primary)
                                if let address = item.placemark.title {
                                    Text(address).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Place name"))
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle("Attach Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let response = try? await MKLocalSearch(request: request).start()
        results = response?.mapItems ?? []
    }

    private func select(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        onSelect(Place(name: item.name ?? query, query: query,
                       latitude: coordinate.latitude, longitude: coordinate.longitude))
        dismiss()
    }
}
