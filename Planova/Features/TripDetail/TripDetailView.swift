import SwiftUI
import CloudKit
import PlanovaKit

struct TripDetailView: View {
    @Environment(AppModel.self) private var model
    let tripID: UUID
    @State private var activeShare: CKShare?
    @State private var shareError: String?

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
                // Participants can't manage someone else's share — only the
                // owner sees the share button.
                if !model.sync.sharedTripIDs.contains(trip.id) {
                    Button {
                        Task {
                            do { activeShare = try await model.sync.share(for: trip) }
                            catch { shareError = error.localizedDescription }
                        }
                    } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                    }
                    .disabled(!model.sync.isAvailable)
                    .accessibilityLabel("Share Trip")
                }
            }
            .sheet(item: $activeShare) { share in
                CloudSharingView(share: share,
                                 container: model.sync.cloudKitContainer,
                                 onStateChange: { Task { await model.sync.fetchNow() } },
                                 onError: { shareError = $0.localizedDescription })
            }
            .alert("Sharing failed", isPresented: Binding(
                get: { shareError != nil },
                set: { if !$0 { shareError = nil } }
            )) {
                Button("OK") { shareError = nil }
            } message: {
                Text(shareError ?? "")
            }
        } else {
            ContentUnavailableView("Trip not found", systemImage: "questionmark.circle")
        }
    }
}

// Adaptation note: @retroactive is valid in Swift 5.7+/5.10. If the compiler
// rejects it for a specific SDK, drop the attribute and silence the warning.
extension CKShare: @retroactive Identifiable {
    public var id: CKRecord.ID { recordID }
}
