import 'session_store.dart';

SessionStore createSessionStore() => _UnavailableStore();

class _UnavailableStore implements SessionStore, SessionArchive {
  @override
  Future<List<String>> listSessionIds() async =>
      throw UnsupportedError('Local session storage is unavailable.');

  @override
  Future<String?> loadById(String sessionId) async {
    validateSessionId(sessionId);
    throw UnsupportedError('Local session storage is unavailable.');
  }

  @override
  Future<String?> loadLatest() async =>
      throw UnsupportedError('Local session storage is unavailable.');

  @override
  Future<void> save(String sessionId, String snapshot) async =>
      throw UnsupportedError('Local session storage is unavailable.');
}
