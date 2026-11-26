import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/session/session_store.dart';
import 'package:phonopticon/session/session_store_io.dart' as io;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'session identifiers reject path traversal before accessing storage',
    () async {
      final store = createSessionStore();
      for (final sessionId in ['', '../other', 'a/b', r'a\b', '.', 'a.json']) {
        await expectLater(
          store.save(sessionId, '{}'),
          throwsArgumentError,
          reason: 'Invalid identifier $sessionId must never reach storage.',
        );
      }
    },
  );

  test(
    'desktop reports unsupported storage instead of claiming persistence',
    () async {
      if (Platform.isAndroid || Platform.isIOS) return;
      final store = createSessionStore();
      await expectLater(store.loadLatest(), throwsUnsupportedError);
      await expectLater(store.save('trial_1', '{}'), throwsUnsupportedError);
    },
  );

  group('mobile storage with an injected local directory', () {
    late Directory temporary;
    late io.MobileSessionStore store;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp(
        'phonopticon-store-test-',
      );
      store = io.MobileSessionStore(directoryResolver: () async => temporary);
    });
    tearDown(() async => temporary.delete(recursive: true));

    test(
      'saves latest deterministically and preserves other sessions',
      () async {
        expect(await store.loadLatest(), isNull);
        await store.save('first', 'first version');
        await store.save('second', 'second version');
        // Deliberately make the older session newer on disk; the pointer wins.
        await File(
          '${temporary.path}/first.json',
        ).setLastModified(DateTime.now().add(const Duration(days: 1)));
        expect(await store.loadLatest(), 'second version');
        await store.save('first', 'first updated');
        expect(await store.loadLatest(), 'first updated');
        expect(
          await File('${temporary.path}/second.json').readAsString(),
          'second version',
        );
        expect(
          await File('${temporary.path}/first.json').readAsString(),
          'first updated',
        );
      },
    );

    test('loads older snapshots if no latest pointer exists', () async {
      final first = File('${temporary.path}/first.json');
      final second = File('${temporary.path}/second.json');
      await first.writeAsString('legacy one');
      await second.writeAsString('legacy two');
      await first.setLastModified(DateTime.utc(2020));
      await second.setLastModified(DateTime.utc(2021));
      expect(await store.loadLatest(), 'legacy two');
      expect(await store.listSessionIds(), ['first', 'second']);
      expect(await store.loadById('first'), 'legacy one');
    });

    test(
      'legacy latest ignores newer files with invalid session names',
      () async {
        final valid = File('${temporary.path}/valid.json');
        final invalid = File('${temporary.path}/not.a.session.json');
        await valid.writeAsString('valid legacy session');
        await invalid.writeAsString('unrelated file');
        await valid.setLastModified(DateTime.utc(2020));
        await invalid.setLastModified(DateTime.utc(2021));
        expect(await store.loadLatest(), 'valid legacy session');
        expect(await invalid.readAsString(), 'unrelated file');
      },
    );

    test(
      'guarded writes reject stale or duplicate session snapshots',
      () async {
        await store.saveIfUnchanged('first', 'v1', expectedSnapshot: null);
        await expectLater(
          store.saveIfUnchanged('first', 'v1', expectedSnapshot: null),
          throwsA(isA<SessionWriteConflict>()),
          reason:
              'An independently created identical record is still a collision.',
        );
        await store.saveIfUnchanged('second', 'other', expectedSnapshot: null);
        await store.saveIfUnchanged('first', 'v2', expectedSnapshot: 'v1');
        await expectLater(
          store.saveIfUnchanged('first', 'stale', expectedSnapshot: 'v1'),
          throwsA(isA<SessionWriteConflict>()),
        );
        await expectLater(
          store.saveIfUnchanged('first', 'duplicate', expectedSnapshot: null),
          throwsA(isA<SessionWriteConflict>()),
        );
        await expectLater(
          store.saveIfUnchanged(
            'missing',
            'unexpected',
            expectedSnapshot: 'prior',
          ),
          throwsA(isA<SessionWriteConflict>()),
        );
        expect(await store.loadById('first'), 'v2');
        expect(await store.loadById('second'), 'other');
        expect(await store.loadLatest(), 'v2');
      },
    );

    test('concurrent guarded saves cannot both replace one baseline', () async {
      await store.saveIfUnchanged('first', 'v1', expectedSnapshot: null);
      Future<String> write(String value) async {
        try {
          await store.saveIfUnchanged('first', value, expectedSnapshot: 'v1');
          return 'saved:$value';
        } on SessionWriteConflict {
          return 'conflict';
        }
      }

      final results = await Future.wait([
        for (var i = 0; i < 12; i++) write('candidate-$i'),
      ]);
      expect(results.where((value) => value == 'conflict'), hasLength(11));
      expect(
        results.where((value) => value.startsWith('saved:')),
        hasLength(1),
      );
      expect(
        'saved:${await store.loadById('first')}',
        results.singleWhere((value) => value.startsWith('saved:')),
      );
    });

    test('a pre-existing save marker blocks without being removed', () async {
      await store.saveIfUnchanged('first', 'v1', expectedSnapshot: null);
      final marker = File('${temporary.path}/.first.write-lock');
      await marker.writeAsString('stale or in use');
      await expectLater(
        store.saveIfUnchanged('first', 'v2', expectedSnapshot: 'v1'),
        throwsA(isA<SessionWriteConflict>()),
      );
      await expectLater(
        store.save('first', 'unsafe'),
        throwsA(isA<SessionWriteConflict>()),
      );
      expect(await marker.readAsString(), 'stale or in use');
      expect(await store.loadById('first'), 'v1');
      await store.saveIfUnchanged(
        'recovered-copy',
        'unsaved changes',
        expectedSnapshot: null,
      );
      expect(await store.loadById('recovered-copy'), 'unsaved changes');
    });

    test('identical retry completes after the pointer update failed', () async {
      await store.saveIfUnchanged('first', 'v1', expectedSnapshot: null);
      final pointer = File('${temporary.path}/.latest');
      await pointer.rename('${temporary.path}/old-pointer');
      final obstruction = Directory('${temporary.path}/.latest');
      await obstruction.create();
      await expectLater(
        store.saveIfUnchanged('first', 'v2', expectedSnapshot: 'v1'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await store.loadById('first'), 'v2');
      await obstruction.delete(); // This empty directory is test-created.
      await store.saveIfUnchanged('first', 'v2', expectedSnapshot: 'v1');
      expect(await store.loadLatest(), 'v2');
      expect(
        await File('${temporary.path}/old-pointer').readAsString(),
        'first',
      );
    });

    test(
      'initial pointer failure cannot adopt an existing identical record',
      () async {
        final obstruction = Directory('${temporary.path}/.latest');
        await obstruction.create();
        await expectLater(
          store.saveIfUnchanged(
            'created',
            'new snapshot',
            expectedSnapshot: null,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await store.loadById('created'), 'new snapshot');
        await obstruction.delete(); // This empty directory is test-created.
        await expectLater(
          store.saveIfUnchanged(
            'created',
            'new snapshot',
            expectedSnapshot: null,
          ),
          throwsA(isA<SessionWriteConflict>()),
        );
        expect(await store.loadById('created'), 'new snapshot');
        await store.saveIfUnchanged(
          'copy',
          'new snapshot',
          expectedSnapshot: null,
        );
        expect(await store.loadLatest(), 'new snapshot');
        expect(await store.loadById('created'), 'new snapshot');
      },
    );

    test('lists and reads saved sessions independently of latest', () async {
      expect(await store.listSessionIds(), isEmpty);
      expect(await store.loadById('missing'), isNull);
      await store.save('second', 'second version');
      await store.save('first', 'first version');
      expect(await store.listSessionIds(), ['first', 'second']);
      expect(await store.loadById('second'), 'second version');
      expect(await store.loadLatest(), 'first version');
      for (final id in ['', '../outside', 'a/b', r'a\b', 'a.json', 'a\n']) {
        await expectLater(store.loadById(id), throwsArgumentError);
      }
    });

    test(
      'ignores invalid filenames and links without hiding raw contents',
      () async {
        await File('${temporary.path}/valid.json').writeAsString('{broken');
        await File('${temporary.path}/bad.name.json').writeAsString('ignored');
        await Directory('${temporary.path}/folder.json').create();
        await Link(
          '${temporary.path}/alias.json',
        ).create('${temporary.path}/valid.json');
        expect(await store.listSessionIds(), ['valid']);
        // Parsing belongs to the caller so a damaged snapshot can be recovered.
        expect(await store.loadById('valid'), '{broken');
        await expectLater(store.loadById('alias'), throwsFormatException);
        await expectLater(store.loadById('folder'), throwsFormatException);
      },
    );

    test('rejects malformed pointers and missing snapshots', () async {
      final pointer = File('${temporary.path}/.latest');
      for (final name in ['', '../outside', 'first.json', 'first\n']) {
        await pointer.writeAsString(name);
        await expectLater(store.loadLatest(), throwsFormatException);
      }
      await pointer.writeAsString('missing');
      await expectLater(store.loadLatest(), throwsFormatException);
    });

    test('reports pointer write failure and retains earlier snapshot', () async {
      await File('${temporary.path}/first.json').writeAsString('previous');
      await Directory('${temporary.path}/.latest').create();
      await expectLater(
        store.save('second', 'new'),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await File('${temporary.path}/first.json').readAsString(),
        'previous',
      );
      // Snapshot replacement precedes the pointer, so this can exist on failure.
      expect(await File('${temporary.path}/second.json').readAsString(), 'new');
      expect(await store.listSessionIds(), ['first', 'second']);
      expect(await store.loadById('second'), 'new');
      await expectLater(store.loadLatest(), throwsFormatException);
    });

    test('surfaces directory resolver errors', () async {
      final broken = io.MobileSessionStore(
        directoryResolver: () async {
          throw StateError('unavailable');
        },
      );
      await expectLater(broken.loadLatest(), throwsStateError);
      await expectLater(broken.listSessionIds(), throwsStateError);
      await expectLater(broken.loadById('valid'), throwsStateError);
      await expectLater(broken.save('valid', '{}'), throwsStateError);
    });
  });
}
