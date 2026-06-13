import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncStateTests {
    @Test func defaultsToDistantPastCursorAndNoTombstones() {
        let s = SyncState()
        #expect(s.cursor == .distantPast)
        #expect(s.tombstones.isEmpty)
    }
    @Test func roundTripsThroughCodable() throws {
        var s = SyncState()
        s.cursor = Date(timeIntervalSince1970: 42)
        let id = UUID()
        s.tombstones[id] = Date(timeIntervalSince1970: 7)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SyncState.self, from: data)
        #expect(back == s)
    }
}
