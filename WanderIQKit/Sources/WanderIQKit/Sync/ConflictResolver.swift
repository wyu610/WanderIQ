import Foundation

/// Pure whole-record last-writer-wins resolution (spec §6.4). Decides what a
/// pull should do with one incoming remote record given local knowledge.
public enum ConflictResolver {
    public enum Decision: Equatable { case applyRemote, keepLocal }

    /// - localModifiedAt: the local entity's modifiedAt, or nil if absent.
    /// - tombstone: local deletion time for this id, or nil if not deleted.
    /// - remoteModifiedAt / remoteDeleted: the incoming record.
    public static func resolve(localModifiedAt: Date?,
                               tombstone: Date?,
                               remoteModifiedAt: Date,
                               remoteDeleted: Bool) -> Decision {
        if remoteDeleted {
            // Remote tombstone wins unless a strictly newer local edit exists.
            if let local = localModifiedAt, local > remoteModifiedAt { return .keepLocal }
            return .applyRemote
        }
        // Remote upsert. A local delete at or after the remote edit wins.
        if let dead = tombstone, dead >= remoteModifiedAt { return .keepLocal }
        // A local value at or after the remote edit wins (ties keep local).
        if let local = localModifiedAt, local >= remoteModifiedAt { return .keepLocal }
        return .applyRemote
    }
}
