import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/audio/audio_backend.dart';
import 'package:phonopticon/calibration/breathing_comparison.dart';
import 'package:phonopticon/calibration/read_bundle.dart';
import 'package:phonopticon/domain/experiment.dart';
import 'package:phonopticon/export/artifacts.dart';
import 'package:phonopticon/main.dart';
import 'package:phonopticon/session/session_store.dart';
import 'package:phonopticon/signal/synthesis.dart';

class _Store implements SessionStore, SessionArchive {
  String? snapshot;
  final Map<String, String> snapshots = {};
  bool failSave = false;
  Completer<void>? openGate;

  @override
  Future<String?> loadLatest() async => snapshot;

  @override
  Future<void> save(String sessionId, String value) async {
    if (failSave) throw StateError('fixture storage failure');
    snapshots[sessionId] = value;
    snapshot = value;
  }

  @override
  Future<List<String>> listSessionIds() async =>
      snapshots.keys.toList()..sort();

  @override
  Future<String?> loadById(String sessionId) async {
    await openGate?.future;
    return snapshots[sessionId];
  }

  Map<String, dynamic> get saved =>
      jsonDecode(snapshot!) as Map<String, dynamic>;
}

class _GuardedStore extends _Store implements GuardedSessionStore {
  @override
  Future<void> saveIfUnchanged(
    String id,
    String value, {
    required String? expectedSnapshot,
  }) async {
    final current = snapshots[id];
    if ((expectedSnapshot == null && current != null) ||
        (expectedSnapshot != null &&
            current != expectedSnapshot &&
            current != value)) {
      throw const SessionWriteConflict('fixture conflict');
    }
    await save(id, value);
  }
}

class _Backend implements AudioBackend {
  int starts = 0;
  bool failNext = false;
  bool syntheticBreathing = false;

  @override
  AudioCapabilities get capabilities =>
      const AudioCapabilities('guided-fixture', 'PHYSICAL', true, 'test only');

  @override
  Future<AudioCapture> start(
    ExperimentConfig config, {
    void Function(double elapsed)? onProgress,
  }) async {
    starts++;
    if (failNext) {
      failNext = false;
      throw StateError('fixture capture failure');
    }
    final emitted = waveform(config);
    return AudioCapture(
      config: config,
      emitted: emitted,
      received: syntheticBreathing && config.mode == ProbeMode.breathing
          ? synthesizeReceived(config, emitted)
          : Float64List.fromList([
              for (var i = 0; i < config.samples; i++)
                .001 * math.sin(2 * math.pi * 440 * i / config.sampleRate),
            ]),
      startedUtc: DateTime.utc(2026),
      sourceKind: 'PHYSICAL',
      backendId: 'guided-fixture',
      deviceMetadata: const {},
    );
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  Future<void> showApp(
    WidgetTester tester,
    _Backend backend,
    _Store store,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      PhonopticonApp(backend: backend, sessionStore: store),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'begin persists without starting audio; notes resume without audio',
    (tester) async {
      final store = _Store();
      final backend = _Backend();
      await showApp(tester, backend, store);
      await tapKey(tester, 'begin-guided');
      expect(backend.starts, 0);
      expect(store.saved['index'], 0);
      expect(store.saved['id'], matches(RegExp(r'^session-\d+-[0-9a-f]{32}$')));
      expect(store.saved['attempts'], isEmpty);

      await tester.ensureVisible(find.text('Session notes'));
      await tester.tap(find.text('Session notes'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('note-unexpectedSounds')),
        'fan running',
      );
      await tapKey(tester, 'save-notes');
      expect((store.saved['notes'] as Map)['unexpectedSounds'], 'fan running');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final resumedBackend = _Backend();
      await showApp(tester, resumedBackend, store);
      await tapKey(tester, 'resume-guided');
      expect(resumedBackend.starts, 0);
      expect(find.text('Trial 1 of 4 · mic-check'), findsOneWidget);
      await tester.ensureVisible(find.text('Session notes'));
      await tester.tap(find.text('Session notes'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('note-unexpectedSounds')))
            .controller!
            .text,
        'fan running',
      );
    },
  );

  testWidgets('a failed capture and its retry are both retained', (
    tester,
  ) async {
    final store = _Store();
    final backend = _Backend()..failNext = true;
    await showApp(tester, backend, store);
    await tapKey(tester, 'begin-guided');
    await tapKey(tester, 'start');
    var attempts = store.saved['attempts'] as List;
    expect(attempts, hasLength(1));
    expect(attempts.first['state'], 'failed');
    expect(attempts.first['error'], contains('fixture capture failure'));
    expect(find.byKey(const Key('next-guided')), findsNothing);
    await tapKey(tester, 'start');
    attempts = store.saved['attempts'] as List;
    expect(attempts, hasLength(2));
    expect(attempts.first['state'], 'failed');
    expect(attempts.last['state'], 'complete');
    expect(attempts.last['bundle'], isA<Map>());
    expect(backend.starts, 2);
    expect(find.byKey(const Key('next-guided')), findsOneWidget);
  });

  testWidgets('guided attempts keep their own notes and completion time', (
    tester,
  ) async {
    final store = _Store();
    final backend = _Backend()..failNext = true;
    await showApp(tester, backend, store);
    await tapKey(tester, 'begin-guided');
    await tester.ensureVisible(find.text('Session notes'));
    await tester.tap(find.text('Session notes'));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('note-unexpectedSounds'));
    await tester.enterText(field, 'fan running');
    await tapKey(tester, 'start');
    await tester.ensureVisible(field);
    await tester.enterText(field, 'fan stopped');
    await tapKey(tester, 'start');
    final attempts = store.saved['attempts'] as List;
    expect(attempts, hasLength(2));
    expect(attempts.first['state'], 'failed');
    expect(attempts.first['operatorNotes']['unexpectedSounds'], 'fan running');
    expect(attempts.last['operatorNotes']['unexpectedSounds'], 'fan stopped');
    expect(DateTime.tryParse(attempts.first['loggedUtc'] as String), isNotNull);
    expect(DateTime.tryParse(attempts.last['loggedUtc'] as String), isNotNull);
  });

  testWidgets(
    'conflict preserves both versions and permits exporting unsaved notes',
    (tester) async {
      final store = _GuardedStore();
      final backend = _Backend();
      await showApp(tester, backend, store);
      await tapKey(tester, 'begin-guided');
      final originalId = store.saved['id'] as String;
      final other = jsonEncode({...store.saved, 'otherWindow': 'preserve'});
      store.snapshots[originalId] = other;

      await tester.ensureVisible(find.text('Session notes'));
      await tester.tap(find.text('Session notes'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('note-unexpectedSounds')),
        'unsaved local observation',
      );
      await tapKey(tester, 'save-notes');
      expect(
        find.textContaining('Session changed in another window'),
        findsOneWidget,
      );
      expect(store.snapshots[originalId], other);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('start'))).onPressed,
        isNull,
      );

      await tester.ensureVisible(
        find.byKey(const Key('export-guided-session')),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('export-guided-session')));
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find
              .textContaining('Temporary file written:')
              .evaluate()
              .isNotEmpty)
            return;
        }
      });
      await tester.pumpAndSettle();
      final status = tester.widget<SelectableText>(
        find.byWidgetPredicate(
          (w) =>
              w is SelectableText &&
              (w.data ?? '').startsWith('Temporary file written:'),
        ),
      );
      final path = status.data!.substring('Temporary file written: '.length);
      final exported = await tester.runAsync(
        () async => jsonDecode(await File(path).readAsString()) as Map,
      );
      expect(
        (exported!['notes'] as Map)['unexpectedSounds'],
        'unsaved local observation',
      );
      expect(store.snapshots[originalId], other);

      await tapKey(tester, 'save-session-copy');
      final copy = store.saved;
      expect(copy['id'], isNot(originalId));
      expect(copy['copiedFromSessionId'], originalId);
      expect(
        (copy['notes'] as Map)['unexpectedSounds'],
        'unsaved local observation',
      );
      expect(store.snapshots[originalId], other);
      expect(backend.starts, 0);
    },
  );

  testWidgets('older saved session opens with its notes and no audio', (
    tester,
  ) async {
    final store = _Store();
    String session(String id, String note, int index) => jsonEncode({
      'schemaVersion': 1,
      'id': id,
      'index': index,
      'attempts': [],
      'notes': {'unexpectedSounds': note},
    });
    await store.save('session-older', session('session-older', 'old fan', 1));
    await store.save('session-newer', session('session-newer', 'new fan', 0));
    final backend = _Backend();
    await showApp(tester, backend, store);
    await tapKey(tester, 'saved-sessions');
    await tapKey(tester, 'open-session-session-older');
    expect(backend.starts, 0);
    expect(find.text('Trial 2 of 4 · stationary'), findsOneWidget);
    await tester.ensureVisible(find.text('Session notes'));
    await tester.tap(find.text('Session notes'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('note-unexpectedSounds')))
          .controller!
          .text,
      'old fan',
    );
  });

  testWidgets('opening a saved session blocks begin and resume until loaded', (
    tester,
  ) async {
    final store = _Store();
    String session(String id) =>
        jsonEncode({'schemaVersion': 1, 'id': id, 'index': 0, 'attempts': []});
    await store.save('session-old', session('session-old'));
    await store.save('session-new', session('session-new'));
    store.openGate = Completer<void>();
    final backend = _Backend();
    await showApp(tester, backend, store);
    await tapKey(tester, 'saved-sessions');
    final target = find.byKey(const Key('open-session-session-old'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('begin-guided')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('resume-guided')))
          .onPressed,
      isNull,
    );
    expect(backend.starts, 0);
    expect(store.snapshots.keys, hasLength(2));
    store.openGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Opened local session session-old.'), findsOneWidget);
    expect(backend.starts, 0);
  });

  testWidgets(
    'malformed saved attempt is rejected without altering snapshots',
    (tester) async {
      final store = _Store();
      final corrupt = jsonEncode({
        'schemaVersion': 1,
        'id': 'session-corrupt',
        'index': 1,
        'attempts': [
          {
            'step': 1,
            'state': 'complete',
            'bundle': {'manifest': 'invalid'},
          },
        ],
      });
      final good = jsonEncode({
        'schemaVersion': 1,
        'id': 'session-good',
        'index': 0,
        'attempts': [],
      });
      await store.save('session-corrupt', corrupt);
      await store.save('session-good', good);
      final backend = _Backend();
      await showApp(tester, backend, store);
      await tapKey(tester, 'saved-sessions');
      await tapKey(tester, 'open-session-session-corrupt');
      expect(
        find.textContaining('Could not open session session-corrupt'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(store.snapshots['session-corrupt'], corrupt);
      expect(store.snapshots['session-good'], good);
      expect(store.snapshot, good);
      expect(backend.starts, 0);
    },
  );

  testWidgets('undecodable saved WAV cannot expose a partial capture', (
    tester,
  ) async {
    final store = _Store();
    final capture = await _Backend().start(const ExperimentConfig());
    final bundle = artifactBundle(capture, null, trialId: 'corrupt-wav');
    (bundle['files'] as Map)['received.wav.base64'] = base64Encode([1, 2, 3]);
    final snapshot = jsonEncode({
      'schemaVersion': 1,
      'id': 'session-corrupt-wav',
      'index': 0,
      'complete': false,
      'attempts': [
        {'step': 0, 'state': 'complete', 'bundle': bundle},
      ],
    });
    await store.save('session-corrupt-wav', snapshot);
    final backend = _Backend();
    await showApp(tester, backend, store);
    await tapKey(tester, 'resume-guided');
    expect(
      find.textContaining('Saved attempt could not be restored'),
      findsWidgets,
    );
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('export'))).onPressed,
      isNull,
    );
    expect(store.snapshot, snapshot);
    expect(backend.starts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'resuming a complete session without mic check clears completion',
    (tester) async {
      final store = _Store();
      final generator = _Backend()..syntheticBreathing = true;
      final attempts = <Map<String, Object?>>[];
      for (final (step, scenario) in [
        (1, Scenario.stationary),
        (2, Scenario.moving),
        (3, Scenario.transmitterOff),
      ]) {
        final capture = await generator.start(
          ExperimentConfig(
            mode: ProbeMode.breathing,
            scenario: scenario,
            durationSeconds: 30,
            motionMeters: .004,
            motionHz: .25,
          ),
        );
        attempts.add({
          'step': step,
          'state': 'complete',
          'bundle': artifactBundle(capture, null, trialId: 'legacy-$step'),
        });
      }
      await store.save(
        'session-legacy',
        jsonEncode({
          'schemaVersion': 1,
          'id': 'session-legacy',
          'index': 3,
          'complete': true,
          'attempts': attempts,
        }),
      );
      final backend = _Backend();
      await showApp(tester, backend, store);
      await tapKey(tester, 'resume-guided');
      await tester.ensureVisible(find.text('Session notes'));
      await tester.tap(find.text('Session notes'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'save-notes');
      expect(store.saved['complete'], isFalse);
      expect((store.saved['attempts'] as List), hasLength(3));
      expect(backend.starts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('jumping to off trial cannot finish incomplete session', (
    tester,
  ) async {
    final store = _Store();
    final backend = _Backend()..syntheticBreathing = true;
    await showApp(tester, backend, store);
    await tapKey(tester, 'begin-guided');
    await tapKey(tester, 'guided-step-selector');
    await tester.tap(find.text('4. transmitter-off').last);
    await tester.pumpAndSettle();
    expect(find.text('Trial 4 of 4 · transmitter-off'), findsOneWidget);
    await tapKey(tester, 'start');
    final finish = find.byKey(const Key('next-guided'));
    expect(finish, findsOneWidget);
    expect(tester.widget<FilledButton>(finish).onPressed, isNull);
    expect(store.saved['complete'], isNot(true));
    expect(store.saved['comparison'], isNull);
    expect(backend.starts, 1);
  });

  testWidgets('guided trial export keeps the saved bundle and trial ID', (
    tester,
  ) async {
    final store = _Store();
    final backend = _Backend();
    await showApp(tester, backend, store);
    await tapKey(tester, 'begin-guided');
    await tapKey(tester, 'start');
    final attempt = (store.saved['attempts'] as List).single as Map;
    final original = Map<String, dynamic>.from(attempt['bundle'] as Map);
    final id = (original['manifest'] as Map)['trialId'] as String;

    await tester.ensureVisible(find.byKey(const Key('export')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('export')));
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find
            .textContaining('Temporary file written:')
            .evaluate()
            .isNotEmpty) {
          return;
        }
      }
    });
    await tester.pumpAndSettle();
    final status = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.data ?? '').startsWith('Temporary file written:'),
      ),
    );
    final path = status.data!.substring('Temporary file written: '.length);
    expect(path, endsWith('/$id.json'));
    final exported = await tester.runAsync(
      () async => jsonDecode(await File(path).readAsString()),
    );
    expect(exported, original);
    expect((exported['manifest'] as Map)['trialId'], id);
    expect(backend.starts, 1);
  });

  testWidgets('comparison follows the selected saved retry', (tester) async {
    final store = _Store();
    final backend = _Backend()..syntheticBreathing = true;
    await showApp(tester, backend, store);
    await tapKey(tester, 'begin-guided');
    await tapKey(tester, 'start');
    await tapKey(tester, 'next-guided');
    await tapKey(tester, 'start');
    await tapKey(tester, 'start');
    final stationaryAttempts = (store.saved['attempts'] as List)
        .where((a) => a['step'] == 1)
        .toList();
    expect(stationaryAttempts, hasLength(2));
    final firstId = stationaryAttempts[0]['bundle']['manifest']['trialId'];
    final retryId = stationaryAttempts[1]['bundle']['manifest']['trialId'];
    expect(firstId, isNot(retryId));
    await tapKey(tester, 'next-guided');
    await tapKey(tester, 'start');
    await tapKey(tester, 'next-guided');
    await tapKey(tester, 'start');
    await tapKey(tester, 'next-guided');
    Map comparison() => store.saved['comparison'] as Map;
    expect((comparison()['trials'] as List).first['trialId'], retryId);

    await tapKey(tester, 'comparison-attempt-1');
    await tester.tap(find.textContaining(firstId as String).last);
    await tester.pumpAndSettle();
    expect((comparison()['trials'] as List).first['trialId'], firstId);
    expect((store.saved['selectedAttempts'] as Map)['1'], 1);
    await tester.ensureVisible(find.text('Quality of selected recordings'));
    await tester.tap(find.text('Quality of selected recordings'));
    await tester.pumpAndSettle();
    expect(find.text('Recording quality · $firstId'), findsOneWidget);
    expect(find.text('Recording quality · $retryId'), findsNothing);
    expect(backend.starts, 5);
  });

  testWidgets('save failure blocks capture until retry saves the session', (
    tester,
  ) async {
    final store = _Store()..failSave = true;
    final backend = _Backend();
    await showApp(tester, backend, store);
    await tapKey(tester, 'begin-guided');
    expect(find.textContaining('Session save failed'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('start'))).onPressed,
      isNull,
    );
    expect(backend.starts, 0);
    store.failSave = false;
    await tapKey(tester, 'retry-save');
    expect(store.saved['index'], 0);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('start'))).onPressed,
      isNotNull,
    );
    expect(backend.starts, 0);
  });

  testWidgets('failed attempt save blocks advancing until retry preserves it', (
    tester,
  ) async {
    final store = _Store();
    final backend = _Backend();
    await showApp(tester, backend, store);
    await tapKey(tester, 'begin-guided');
    store.failSave = true;
    await tapKey(tester, 'start');
    expect(backend.starts, 1);
    expect(store.saved['attempts'], isEmpty);
    expect(find.byKey(const Key('next-guided')), findsNothing);
    expect(find.textContaining('Session save failed'), findsOneWidget);
    store.failSave = false;
    await tapKey(tester, 'retry-save');
    expect((store.saved['attempts'] as List).single['state'], 'complete');
    expect(find.byKey(const Key('next-guided')), findsOneWidget);
    expect(backend.starts, 1);
  });

  testWidgets(
    'guided completion compares saved physical-labelled synthetic captures',
    (tester) async {
      final store = _Store();
      final backend = _Backend()..syntheticBreathing = true;
      await showApp(tester, backend, store);
      await tapKey(tester, 'begin-guided');
      expect(backend.starts, 0);
      for (var step = 0; step < 4; step++) {
        expect(find.textContaining('Trial ${step + 1} of 4'), findsOneWidget);
        expect(backend.starts, step);
        await tapKey(tester, 'start');
        expect(backend.starts, step + 1);
        expect(find.byKey(const Key('next-guided')), findsOneWidget);
        await tapKey(tester, 'next-guided');
        expect(backend.starts, step + 1);
      }

      final session = store.saved;
      expect(session['complete'], isTrue);
      final attempts = session['attempts'] as List;
      expect(attempts, hasLength(4));
      final bundles = [
        for (final a in attempts.skip(1))
          Map<String, dynamic>.from(a['bundle'] as Map),
      ];
      expect(bundles, hasLength(3));
      final captures = [
        for (final b in bundles)
          readPhysicalBundle(b, mode: ProbeMode.breathing),
      ];
      final expected = compareBreathingCaptures(
        captures,
        trialIds: [
          for (final b in bundles) (b['manifest'] as Map)['trialId'] as String?,
        ],
        sourceRevisions: [
          for (final b in bundles)
            (b['manifest'] as Map)['sourceRevision'] as String?,
        ],
      );
      final comparison = session['comparison'] as Map;
      expect(comparison, expected);
      expect(comparison['physicalValidation'], isFalse);
      final met = comparison['calibrationCriteriaMet'] as bool;
      expect(
        find.text('Calibration criteria ${met ? 'met' : 'not met'}'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Stationary control quiet: ${comparison['stationaryControlQuiet']}',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Fixed periodic fraction ≥ 25%'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('export-guided-session')), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('export-guided-session')),
            )
            .onPressed,
        isNotNull,
      );
      expect(backend.starts, 4);
    },
  );
}
