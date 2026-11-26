import 'dart:async';
import 'dart:html' as html;
import 'session_store.dart';

SessionStore createSessionStore() => _BrowserSessionStore();

class _BrowserSessionStore
    implements SessionStore, SessionArchive, GuardedSessionStore {
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

  @override
  Future<void> saveIfUnchanged(
    String sessionId,
    String snapshot, {
    required String? expectedSnapshot,
  }) async {
    validateSessionId(sessionId);
    final db = await _open();
    try {
      // IndexedDB serializes readwrite transactions for this object store.
      // Enqueue the writes in the read request's success callback: some
      // browsers may deactivate a transaction after an awaited Future.
      final transaction = db.transaction('sessions', 'readwrite');
      final completed = transaction.completed as Future<dynamic>;
      // The transaction may fail before a request future completes; attach an
      // error listener immediately while still awaiting its eventual outcome.
      completed.ignore();
      final store = transaction.objectStore('sessions');
      final key = 'session:$sessionId';
      final staged = Completer<void>();
      // getAll distinguishes a missing key (empty list) from a stored null.
      final dynamic request = store.getAll(key, 1);
      (request.onSuccess as Stream).listen((_) {
        try {
          final dynamic values = request.result;
          if (values is! List || values.length > 1) {
            throw const FormatException('Invalid session lookup result.');
          }
          final present = values.isNotEmpty;
          final dynamic current = present ? values.single : null;
          if (present && current is! String) {
            throw const FormatException('Invalid session snapshot.');
          }
          if ((!present && expectedSnapshot != null) ||
              (present &&
                  (expectedSnapshot == null ||
                      (current != expectedSnapshot && current != snapshot)))) {
            throw const SessionWriteConflict(
              'This session changed elsewhere. Export your current work or save it as a new session.',
            );
          }
          Future.wait<dynamic>([
            store.put(snapshot, key) as Future<dynamic>,
            store.put(sessionId, 'latest') as Future<dynamic>,
          ]).then(
            (_) {
              if (!staged.isCompleted) staged.complete();
            },
            onError: (Object error, StackTrace stack) {
              if (!staged.isCompleted) staged.completeError(error, stack);
            },
          );
        } catch (error, stack) {
          // No successful write may be committed if scheduling either put
          // throws synchronously. Abort also leaves the previous pointer.
          try {
            transaction.abort();
          } catch (_) {}
          if (!staged.isCompleted) staged.completeError(error, stack);
        }
      });
      (request.onError as Stream).listen((dynamic error) {
        if (!staged.isCompleted) staged.completeError(error);
      });
      await staged.future;
      await completed;
    } finally {
      db.close();
    }
  }
}
