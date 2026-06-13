import Foundation

public enum EntityKind: String, Codable, Sendable, CaseIterable {
    case trip, day, item
}

public enum SyncOp: String, Codable, Sendable {
    case upsert, delete
}

/// Stable coalescing key: one pending change per (kind, id).
public struct EntityKey: Hashable, Codable, Sendable {
    public let kind: EntityKind
    public let id: UUID
    public init(kind: EntityKind, id: UUID) { self.kind = kind; self.id = id }
}

/// An outbox entry. Payload is read from the store at push time, so the entry
/// only needs to reference the entity and carry the relevant timestamp.
public struct PendingChange: Equatable, Codable, Sendable {
    public let kind: EntityKind
    public let id: UUID
    public let tripID: UUID
    public let op: SyncOp
    public let modifiedAt: Date

    public init(kind: EntityKind, id: UUID, tripID: UUID, op: SyncOp, modifiedAt: Date) {
        self.kind = kind; self.id = id; self.tripID = tripID
        self.op = op; self.modifiedAt = modifiedAt
    }
    public var key: EntityKey { EntityKey(kind: kind, id: id) }
}

/// A remote record as exchanged with the backend. `fields` carries the entity
/// payload for upserts; nil/ignored for tombstones. Kept JSON-shaped so the
/// same record format serves the conformance suite and the TS engine.
public struct SyncRecord: Equatable, Codable, Sendable {
    public let kind: EntityKind
    public let id: UUID
    public let tripID: UUID
    public let modifiedAt: Date
    public let deleted: Bool
    public let fields: [String: String]?

    public init(kind: EntityKind, id: UUID, tripID: UUID, modifiedAt: Date,
                deleted: Bool, fields: [String: String]? = nil) {
        self.kind = kind; self.id = id; self.tripID = tripID
        self.modifiedAt = modifiedAt; self.deleted = deleted; self.fields = fields
    }
}
