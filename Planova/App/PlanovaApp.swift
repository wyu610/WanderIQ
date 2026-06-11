import SwiftUI

@main
struct PlanovaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            TripListView()
                .environment(model)
        }
    }
}
