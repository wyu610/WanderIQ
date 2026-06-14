#if DEBUG
import Foundation
import WanderIQKit

/// Manual smoke check for the Supabase transport wiring. Call from a temporary
/// button or `Task {}` in the app during 3a bring-up; remove/ignore after 3b.
enum SyncDebug {
    static func smoke() async {
        let backend = SupabaseRemoteSyncBackend()
        do {
            let page = try await backend.changes(since: .distantPast)
            print("SyncDebug: pulled \(page.records.count) records, cursor \(page.cursor)")
        } catch {
            print("SyncDebug: changes() failed: \(error)")
        }
    }
}
#endif
