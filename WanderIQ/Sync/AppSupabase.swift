import Foundation
import Supabase

/// The single app-wide Supabase client. Auth and the sync transport share it
/// so they share one Keychain-persisted session. supabase-swift defaults to
/// KeychainLocalStorage for auth on Apple platforms, so sessions survive
/// relaunches automatically.
enum AppSupabase {
    static let client = SupabaseClient(supabaseURL: SupabaseConfig.url,
                                       supabaseKey: SupabaseConfig.anonKey)
}
