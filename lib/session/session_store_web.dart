import 'dart:html' as html;
import 'session_store.dart';

SessionStore createSessionStore() => _BrowserSessionStore();

class _BrowserSessionStore implements SessionStore, SessionArchive {
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
  Future<List<String>> listSessionIds() async {
    final db = await _open();
    try {
      final transaction = db.transaction('sessions', 'readonly');
      final store = transaction.objectStore('sessions');
      final ids = <String>[];
      await for (final dynamic cursor
          in store.openCursor(autoAdvance: true) as Stream) {
        final dynamic key = cursor.key;
        if (key is! String || !key.startsWith('session:')) continue;
        final id = key.substring('session:'.length);
        if (isValidSessionId(id)) ids.add(id);
      }
      ids.sort();
      return ids;
    } finally {
      db.close();
    }
  }

  @override
  Future<String?> loadById(String sessionId) async {
    validateSessionId(sessionId);
    final db = await _open();
    try {
      final transaction = db.transaction('sessions', 'readonly');
      final store = transaction.objectStore('sessions');
      final key = 'session:$sessionId';
      // Queue both requests before awaiting so the transaction stays active.
      // A stored null is corrupt, whereas a missing key is an absent session.
      final results = await Future.wait<dynamic>([
        store.getObject(key) as Future<dynamic>,
        store.count(key) as Future<dynamic>,
      ]);
      final dynamic value = results[0];
      if (results[1] == 0) return null;
      if (value is! String) {
        throw const FormatException('Invalid session snapshot.');
      }
      return value;
    } finally {
      db.close();
    }
  }

  @override
  Future<void> save(String sessionId, String snapshot) async {
    validateSessionId(sessionId);
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
