import 'session_store_stub.dart'
    if (dart.library.io) 'session_store_io.dart'
    if (dart.library.html) 'session_store_web.dart'
    as platform;

/// Snapshots are replaced atomically. A failed save can still have replaced a
/// snapshot if a subsequent latest-session pointer update fails; callers must
/// treat the outcome as uncertain and allow a retry without discarding data.
abstract interface class SessionStore {
  Future<String?> loadLatest();
  Future<void> save(String sessionId, String snapshot);
}

/// Optional access to all saved sessions. Snapshot contents are returned as
/// stored; callers must validate their format and schema before using them.
abstract interface class SessionArchive {
  /// Lists valid session identifiers in lexicographic order.
  Future<List<String>> listSessionIds();

  /// Returns null for a missing snapshot and throws for an invalid identifier.
  Future<String?> loadById(String sessionId);
}

final _sessionIdentifier = RegExp(r'^[a-zA-Z0-9_-]+$');

bool isValidSessionId(String value) {
  final match = _sessionIdentifier.matchAsPrefix(value);
  return match != null && match.end == value.length;
}

void validateSessionId(String value) {
  if (!isValidSessionId(value)) {
    throw ArgumentError.value(value, 'sessionId', 'Invalid session identifier');
  }
}

SessionStore createSessionStore() => platform.createSessionStore();
