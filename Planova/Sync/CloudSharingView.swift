import SwiftUI
import CloudKit
import UIKit
import PlanovaKit

/// SwiftUI wrapper for UICloudSharingController, presented from the trip
/// detail's Share button once the CKShare exists.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: Error) {}
        func itemTitle(for controller: UICloudSharingController) -> String? {
            controller.share?[CKShare.SystemFieldKey.title] as? String
        }
        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {}
        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {}
    }
}
