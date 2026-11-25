import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/audio/audio_backend.dart';
import 'package:phonopticon/calibration/breathing_comparison.dart';
import 'package:phonopticon/calibration/read_bundle.dart';
import 'package:phonopticon/domain/experiment.dart';
import 'package:phonopticon/main.dart';
import 'package:phonopticon/session/session_store.dart';
import 'package:phonopticon/signal/synthesis.dart';

class _Store implements SessionStore {
  String? snapshot;
  bool failSave = false;

  @override
  Future<String?> loadLatest() async => snapshot;

  @override
  Future<void> save(String sessionId, String value) async {
    if (failSave) throw StateError('fixture storage failure');
    snapshot = value;
  }

  Map<String, dynamic> get saved =>
      jsonDecode(snapshot!) as Map<String, dynamic>;
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
