import 'session_store.dart';

SessionStore createSessionStore() => _UnavailableStore();

class _UnavailableStore implements SessionStore {
  @override
  Future<String?> loadLatest() async =>
      throw UnsupportedError('Local session storage is unavailable.');

  @override
  Future<void> save(String sessionId, String snapshot) async =>
      throw UnsupportedError('Local session storage is unavailable.');
}
