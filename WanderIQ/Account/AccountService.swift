import Foundation
import Supabase

/// Account-level operations over Supabase. `deleteAccount` invokes the
/// `delete_my_account` RPC (SECURITY DEFINER), which removes the caller's
/// auth.users row and cascades away all of their trips and memberships.
@MainActor
final class AccountService {
    private let client = AppSupabase.client

    func deleteAccount() async throws {
        _ = try await client.rpc("delete_my_account").execute()
    }
}
