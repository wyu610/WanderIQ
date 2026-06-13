import Foundation

/// Insertion-ordered, key-coalesced set of pending changes (spec §6.2).
/// One entry per (kind, id); the newest enqueue for a key replaces the older
/// but keeps the original queue position so flush order stays stable.
public struct Outbox: Equatable, Codable, Sendable {
    private var order: [EntityKey] = []
    private var byKey: [EntityKey: PendingChange] = [:]

    public init() {}

    public var pending: [PendingChange] { order.compactMap { byKey[$0] } }

    public mutating func enqueue(_ change: PendingChange) {
        if byKey[change.key] == nil { order.append(change.key) }
        byKey[change.key] = change
    }

    public mutating func acknowledge(_ key: EntityKey) {
        byKey[key] = nil
        order.removeAll { $0 == key }
    }

    public var isEmpty: Bool { byKey.isEmpty }

    // Codable: persist as the ordered pending list; rebuild the index on decode.
    private enum CodingKeys: String, CodingKey { case pending }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = try c.decode([PendingChange].self, forKey: .pending)
        for change in list { enqueue(change) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pending, forKey: .pending)
    }
}
