enum ConflictResolution {
  useLocal,
  useRemote,
  conflict,
  delete,
}

class ResolutionResult {
  final ConflictResolution action;
  final Map<String, dynamic>? mergedPayload;

  ResolutionResult(this.action, [this.mergedPayload]);
}

/// Pull-side resolution. `localVersion` is the server version this device last
/// saw (it is no longer bumped on local edits), so:
/// - a clean local copy takes the remote one whenever the server has moved on;
/// - a dirty local copy is never overwritten by a pull. Its queued push carries
///   the base version, and the server, which sees both sides, answers
///   "conflict" if someone else changed the record in the meantime.
/// Timestamps are not compared: the server clock and the device clock differ.
class ConflictResolver {
  static ResolutionResult resolve({
    required String entityType,
    required bool localIsDirty,
    required int localVersion,
    required DateTime localUpdatedAt,
    required bool localIsDeleted,
    required int remoteVersion,
    required DateTime remoteUpdatedAt,
    required bool remoteIsDeleted,
    required Map<String, dynamic> localPayload,
    required Map<String, dynamic> remotePayload,
  }) {
    if (remoteIsDeleted || localIsDeleted) return ResolutionResult(ConflictResolution.delete);
    if (localIsDirty) return ResolutionResult(ConflictResolution.useLocal);
    if (remoteVersion > localVersion) return ResolutionResult(ConflictResolution.useRemote);
    return ResolutionResult(ConflictResolution.useLocal);
  }
}
