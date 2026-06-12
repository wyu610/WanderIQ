import SwiftUI
import CloudKit
import UIKit

@main
struct PlanovaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            TripListView()
                .environment(model)
        }
    }

    init() {}
}

/// Routes CloudKit share-invitation acceptance into the sync coordinator.
/// SwiftUI apps receive userDidAcceptCloudKitShareWith via a scene delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static weak var sharedModel: AppModel?

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        guard let model = AppDelegate.sharedModel else { return }
        Task { @MainActor in
            await model.sync.acceptShare(metadata: metadata)
        }
    }
}
