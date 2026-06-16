import SwiftUI

@main
struct WanderIQApp: App {
    @State private var model = AppModel()
    @State private var auth = AuthController()

    init() { Theme.apply() }

    var body: some Scene {
        WindowGroup {
            Group {
                switch auth.phase {
                case .loading:
                    ProgressView()
                case .signedOut:
                    AuthView()
                case .signedIn:
                    TripListView()
                        .environment(model)
                        .task { await model.sync.start() }
                }
            }
            .environment(auth)
            .tint(.wTerracotta)
        }
    }
}
