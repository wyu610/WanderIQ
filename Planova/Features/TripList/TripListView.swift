import SwiftUI
import PlanovaKit

struct TripListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text("Planova — \(model.store.trips.count) trips")
    }
}
