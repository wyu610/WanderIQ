import Testing
import Foundation
@testable import WanderIQKit

@Suite struct SyncStoreTests {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @Test func savesAndLoadsOutboxAndState() throws {
        let store = SyncStore(directory: tempDir())
        var box = Outbox()
        box.enqueue(PendingChange(kind: .item, id: UUID(), tripID: UUID(),
                                  op: .upsert, modifiedAt: Date(timeIntervalSince1970: 3)))
        var state = SyncState(); state.cursor = Date(timeIntervalSince1970: 9)
        try store.save(outbox: box, state: state)

        let loaded = store.load()
        #expect(loaded.outbox.pending.count == 1)
        #expect(loaded.state.cursor == Date(timeIntervalSince1970: 9))
    }

    @Test func loadReturnsEmptyDefaultsWhenAbsent() {
        let loaded = SyncStore(directory: tempDir()).load()
        #expect(loaded.outbox.isEmpty)
        #expect(loaded.state.cursor == .distantPast)
    }
}
