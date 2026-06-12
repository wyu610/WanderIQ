import SwiftUI
import CloudKit
import UIKit
import PlanovaKit

/// SwiftUI wrapper for UICloudSharingController, presented from the trip
/// detail's Share button once the CKShare exists.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    /// Called after the controller saves or stops the share, so the sync
    /// coordinator can reconcile shared-zone state.
    var onStateChange: () -> Void = {}
    /// Called when the controller fails to save the share — without this the
    /// user believes the trip was shared when it wasn't.
    var onError: (Error) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onStateChange: onStateChange, onError: onError)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let onStateChange: () -> Void
        private let onError: (Error) -> Void

        init(onStateChange: @escaping () -> Void, onError: @escaping (Error) -> Void) {
            self.onStateChange = onStateChange
            self.onError = onError
        }

        func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onError(error)
        }

        func itemTitle(for controller: UICloudSharingController) -> String? {
            controller.share?[CKShare.SystemFieldKey.title] as? String
        }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            onStateChange()
        }

        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            onStateChange()
        }
    }
}
