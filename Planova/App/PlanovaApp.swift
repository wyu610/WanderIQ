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
}

/// Routes CloudKit share-invitation acceptance into the sync coordinator.
/// SwiftUI apps receive userDidAcceptCloudKitShareWith via a scene delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    @MainActor static weak var sharedModel: AppModel?
    /// Metadata that arrived before AppModel finished initializing
    /// (cold-start launch from a share link); drained by AppModel.init.
    @MainActor static var pendingShareMetadata: CKShare.Metadata?

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {

    /// Cold start from a share link: the metadata arrives in the connection
    /// options, not via userDidAcceptCloudKitShareWith.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Self.accept(metadata)
        }
    }

    /// Warm path: app already running when the user taps the invite.
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Self.accept(metadata)
    }

    private static func accept(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            if let model = AppDelegate.sharedModel {
                await model.sync.acceptShare(metadata: metadata)
            } else {
                AppDelegate.pendingShareMetadata = metadata
            }
        }
    }
}
