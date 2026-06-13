import Testing
import Foundation
@testable import WanderIQKit

@Suite struct ConflictResolverTests {
    let t1 = Date(timeIntervalSince1970: 1)
    let t2 = Date(timeIntervalSince1970: 2)
    let t3 = Date(timeIntervalSince1970: 3)

    @Test func remoteUpsertNewerThanLocalApplies() {
        #expect(ConflictResolver.resolve(localModifiedAt: t1, tombstone: nil,
                                         remoteModifiedAt: t2, remoteDeleted: false) == .applyRemote)
    }
    @Test func remoteUpsertOlderThanLocalKept() {
        #expect(ConflictResolver.resolve(localModifiedAt: t2, tombstone: nil,
                                         remoteModifiedAt: t1, remoteDeleted: false) == .keepLocal)
    }
    @Test func tieKeepsLocal() {
        #expect(ConflictResolver.resolve(localModifiedAt: t2, tombstone: nil,
                                         remoteModifiedAt: t2, remoteDeleted: false) == .keepLocal)
    }
    @Test func remoteDeleteNewerThanLocalEditApplies() {
        #expect(ConflictResolver.resolve(localModifiedAt: t1, tombstone: nil,
                                         remoteModifiedAt: t2, remoteDeleted: true) == .applyRemote)
    }
    @Test func localEditNewerThanRemoteDeleteKept() {
        #expect(ConflictResolver.resolve(localModifiedAt: t3, tombstone: nil,
                                         remoteModifiedAt: t2, remoteDeleted: true) == .keepLocal)
    }
    @Test func localTombstoneAtOrAfterRemoteUpsertIgnoresRemote() {
        // Local delete at t2 vs remote upsert at t2 → stays deleted.
        #expect(ConflictResolver.resolve(localModifiedAt: nil, tombstone: t2,
                                         remoteModifiedAt: t2, remoteDeleted: false) == .keepLocal)
    }
    @Test func remoteUpsertNewerThanLocalTombstoneResurrects() {
        #expect(ConflictResolver.resolve(localModifiedAt: nil, tombstone: t1,
                                         remoteModifiedAt: t2, remoteDeleted: false) == .applyRemote)
    }
    @Test func remoteUpsertForUnknownEntityApplies() {
        #expect(ConflictResolver.resolve(localModifiedAt: nil, tombstone: nil,
                                         remoteModifiedAt: t1, remoteDeleted: false) == .applyRemote)
    }
}
