import Foundation

/// Persists the Outbox and SyncState as two JSON files in `directory`
/// (mirrors TripRepository's approach). Family-scale data; no SQLite needed.
public struct SyncStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    private var outboxURL: URL { directory.appendingPathComponent("outbox.json") }
    private var stateURL: URL { directory.appendingPathComponent("sync-state.json") }

    private var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
    private var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    public func load() -> (outbox: Outbox, state: SyncState) {
        let outbox = (try? Data(contentsOf: outboxURL))
            .flatMap { try? decoder.decode(Outbox.self, from: $0) } ?? Outbox()
        let state = (try? Data(contentsOf: stateURL))
            .flatMap { try? decoder.decode(SyncState.self, from: $0) } ?? SyncState()
        return (outbox, state)
    }

    public func save(outbox: Outbox, state: SyncState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(outbox).write(to: outboxURL, options: .atomic)
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }
}
