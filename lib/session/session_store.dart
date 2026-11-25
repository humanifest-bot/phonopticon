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

SessionStore createSessionStore() => platform.createSessionStore();
