import 'dart:html' as html;
import 'session_store.dart';

SessionStore createSessionStore() => _BrowserSessionStore();

class _BrowserSessionStore implements SessionStore {
  Future<dynamic> _open() {
    final factory = html.window.indexedDB;
    if (factory == null) {
      throw UnsupportedError('Local session storage is unavailable.');
    }
    return factory.open(
      'phonopticon-sessions',
      version: 1,
      onUpgradeNeeded: (event) {
        final dynamic request = event.target;
        request.result.createObjectStore('sessions');
      },
    );
  }

  @override
  Future<String?> loadLatest() async {
    final db = await _open();
    try {
      final first = db.transaction('sessions', 'readonly');
      final dynamic sessionId = await first
          .objectStore('sessions')
          .getObject('latest');
      if (sessionId == null) return null;
      final second = db.transaction('sessions', 'readonly');
      final value = await second
          .objectStore('sessions')
          .getObject('session:$sessionId');
      if (value is! String) {
        throw StateError('The latest saved session could not be read.');
      }
      return value;
    } finally {
      db.close();
    }
  }

  @override
  Future<void> save(String sessionId, String snapshot) async {
    final db = await _open();
    try {
      final transaction = db.transaction('sessions', 'readwrite');
      final completed = transaction.completed;
      final store = transaction.objectStore('sessions');
      await Future.wait<dynamic>([
        store.put(snapshot, 'session:$sessionId') as Future<dynamic>,
        store.put(sessionId, 'latest') as Future<dynamic>,
      ]);
      await completed;
    } finally {
      db.close();
    }
  }
}
