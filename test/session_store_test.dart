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
