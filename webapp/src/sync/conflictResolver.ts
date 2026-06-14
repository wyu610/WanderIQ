export type Decision = "applyRemote" | "keepLocal";

/**
 * Pure whole-record last-writer-wins (protocol §"Pull"). Mirrors the Swift
 * ConflictResolver exactly so both engines pass sync-conformance.json.
 * Times are epoch numbers; null means "absent".
 */
export function resolve(
  localModifiedAt: number | null,
  tombstone: number | null,
  remoteModifiedAt: number,
  remoteDeleted: boolean,
): Decision {
  if (remoteDeleted) {
    if (localModifiedAt !== null && localModifiedAt > remoteModifiedAt) return "keepLocal";
    return "applyRemote";
  }
  if (tombstone !== null && tombstone >= remoteModifiedAt) return "keepLocal";
  if (localModifiedAt !== null && localModifiedAt >= remoteModifiedAt) return "keepLocal";
  return "applyRemote";
}
