import Foundation
import Supabase

/// A trip_members row (subset) for display. Property names match the Postgres
/// columns (supabase-swift's decoder does not convert snake_case).
struct TripMember: Decodable, Identifiable, Sendable {
    let id: UUID
    let role: String          // "viewer" | "editor"
    let status: String        // "pending" | "accepted"
    let invited_email: String?
    let user_id: UUID?
}

/// Per-trip sharing over Supabase. Add/list are owner-gated by RLS;
/// claimInvites links this user to pending invites for their email.
@MainActor
final class SharingService {
    private let client = AppSupabase.client

    func members(tripID: UUID) async throws -> [TripMember] {
        try await client.from("trip_members")
            .select("id, role, status, invited_email, user_id")
            .eq("trip_id", value: tripID.uuidString.lowercased())
            .order("created_at", ascending: true)
            .execute().value
    }

    func addMember(tripID: UUID, email: String, role: String) async throws {
        struct NewMember: Encodable {
            let trip_id: String
            let invited_email: String
            let role: String
            let status: String
        }
        try await client.from("trip_members").insert(
            NewMember(trip_id: tripID.uuidString.lowercased(),
                      invited_email: email, role: role, status: "pending")
        ).execute()
    }

    func claimInvites() async throws {
        _ = try await client.rpc("claim_invites").execute()
    }
}
