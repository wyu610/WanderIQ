import Foundation
import Supabase
import WanderIQKit

/// Concrete RemoteSyncBackend backed by Supabase PostgREST. Tables: trips,
/// trip_days, trip_items. server_updated_at is server-stamped (trigger);
/// the cursor filters on it. RLS scopes rows to the signed-in user.
final class SupabaseRemoteSyncBackend: RemoteSyncBackend {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    convenience init() {
        self.init(client: AppSupabase.client)
    }

    // MARK: Push

    func send(_ records: [SyncRecord]) async throws {
        // owner_id is NOT NULL and RLS requires it == auth.uid(); the pure
        // mapper can't know the user, so inject it here. Requires an
        // authenticated session (arrives in 3b) — push is a no-op pre-auth.
        let uid = try await client.auth.session.user.id.uuidString.lowercased()
        var trips = records.filter { $0.kind == .trip }.map(SupabaseRowMapping.tripRow(from:))
        for i in trips.indices { trips[i].owner_id = uid }
        let days  = records.filter { $0.kind == .day  }.map(SupabaseRowMapping.dayRow(from:))
        let items = records.filter { $0.kind == .item }.map(SupabaseRowMapping.itemRow(from:))
        if !trips.isEmpty { try await client.from("trips").upsert(trips, onConflict: "id").execute() }
        if !days.isEmpty  { try await client.from("trip_days").upsert(days, onConflict: "id").execute() }
        if !items.isEmpty { try await client.from("trip_items").upsert(items, onConflict: "id").execute() }
    }

    // MARK: Pull

    func changes(since cursor: Date) async throws -> ChangePage {
        let iso = ISO8601DateFormatter().string(from: cursor)
        async let tripRows: [TripRow] = client.from("trips").select()
            .gt("server_updated_at", value: iso)
            .order("server_updated_at", ascending: true).execute().value
        async let dayRows: [DayRow] = client.from("trip_days").select()
            .gt("server_updated_at", value: iso)
            .order("server_updated_at", ascending: true).execute().value
        async let itemRows: [ItemRow] = client.from("trip_items").select()
            .gt("server_updated_at", value: iso)
            .order("server_updated_at", ascending: true).execute().value

        let records =
            try await tripRows.map(SupabaseRowMapping.syncRecord(trip:)) +
            (try await dayRows.map(SupabaseRowMapping.syncRecord(day:))) +
            (try await itemRows.map(SupabaseRowMapping.syncRecord(item:)))

        let newCursor = try await maxServerUpdatedAt(defaulting: cursor)
        return ChangePage(records: records, cursor: newCursor)
    }

    /// The max server_updated_at across the three tables visible to this user,
    /// or `fallback` if there are none. Decoded as ISO strings to avoid date
    /// decoding-strategy coupling.
    private func maxServerUpdatedAt(defaulting fallback: Date) async throws -> Date {
        struct Stamp: Decodable { let server_updated_at: String }
        func newest(_ table: String) async throws -> Date? {
            let rows: [Stamp] = try await client.from(table).select("server_updated_at")
                .order("server_updated_at", ascending: false).limit(1).execute().value
            return rows.first.flatMap { ISO8601DateFormatter().date(from: $0.server_updated_at) }
        }
        let stamps = [try await newest("trips"),
                      try await newest("trip_days"),
                      try await newest("trip_items")].compactMap { $0 }
        return stamps.max() ?? fallback
    }
}
