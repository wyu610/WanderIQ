import SwiftUI
import MapKit
import WanderIQKit

/// MKLocalSearch-backed picker; returns a Place with resolved coordinates.
struct PlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Place) -> Void

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    if hasSearched {
                        ContentUnavailableView("No results", systemImage: "mappin.slash",
                                               description: Text("Check the name or try a different spelling."))
                    } else {
                        ContentUnavailableView("Search for a place", systemImage: "magnifyingglass",
                                               description: Text("Type a name and press Search."))
                    }
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
            .onSubmit(of: .search) {
                searchTask?.cancel()
                searchTask = Task { await search() }
            }
            .onDisappear { searchTask?.cancel() }
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
        request.resultTypes = .pointOfInterest
        let response = try? await MKLocalSearch(request: request).start()
        guard !Task.isCancelled else { return }
        results = response?.mapItems ?? []
        hasSearched = true
    }

    private func select(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        onSelect(Place(name: item.name ?? query, query: query,
                       latitude: coordinate.latitude, longitude: coordinate.longitude))
        dismiss()
    }
}
