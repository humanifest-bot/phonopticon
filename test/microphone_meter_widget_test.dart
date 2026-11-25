import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/audio/audio_backend.dart';
import 'package:phonopticon/domain/experiment.dart';
import 'package:phonopticon/main.dart';
import 'package:phonopticon/session/session_store.dart';

class _MemoryStore implements SessionStore {
  @override
  Future<String?> loadLatest() async => null;

  @override
  Future<void> save(String sessionId, String snapshot) async {}
}

class _MeterBackend implements AudioBackend, MicrophoneMeterBackend {
  int meterStarts = 0;
  int meterStops = 0;
  int trialStarts = 0;
  Completer<void>? _meter;
  void Function(double)? onLevel;

  @override
  AudioCapabilities get capabilities =>
      const AudioCapabilities('meter-fixture', 'PHYSICAL', true, 'Fixture');

  @override
  Future<void> startMeter({required void Function(double level) onLevel}) {
    meterStarts++;
    this.onLevel = onLevel;
    _meter = Completer<void>();
    return _meter!.future;
  }

  @override
  Future<void> stopMeter() async {
    meterStops++;
    if (_meter != null && !_meter!.isCompleted) _meter!.complete();
  }

  @override
  Future<AudioCapture> start(
    ExperimentConfig config, {
    void Function(double elapsed)? onProgress,
  }) async {
    trialStarts++;
    throw StateError('A meter check must not start a trial or play a probe');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  Future<void> showApp(WidgetTester tester, _MeterBackend backend) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      PhonopticonApp(backend: backend, sessionStore: _MemoryStore()),
    );
    await tester.pump();
  }

  testWidgets('explicit meter check displays level without starting a trial', (
    tester,
  ) async {
    final backend = _MeterBackend();
    await showApp(tester, backend);
    final startMeter = find.byKey(const Key('start-meter'));
    final stopMeter = find.byKey(const Key('stop-meter'));
    final startTrial = find.byKey(const Key('start'));

    expect(backend.meterStarts, 0);
    await tester.ensureVisible(startMeter);
    await tester.tap(startMeter);
    await tester.pump();
    expect(backend.meterStarts, 1);
    expect(backend.trialStarts, 0);
    expect(tester.widget<FilledButton>(startTrial).onPressed, isNull);

    backend.onLevel!(0.42);
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byKey(const Key('meter-level')))
          .value,
      closeTo(0.42, 0.0001),
    );
    await tester.ensureVisible(stopMeter);
    await tester.tap(stopMeter);
    await tester.pump();
    expect(backend.meterStops, 1);
    expect(backend.trialStarts, 0);
    expect(tester.widget<FilledButton>(startTrial).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving the foreground stops the meter without restarting it', (
    tester,
  ) async {
    final backend = _MeterBackend();
    await showApp(tester, backend);
    final startMeter = find.byKey(const Key('start-meter'));
    await tester.ensureVisible(startMeter);
    await tester.tap(startMeter);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(backend.meterStops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(backend.meterStarts, 1);
    expect(backend.trialStarts, 0);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('start'))).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('meter controls remain usable at narrow width and large text', (
    tester,
  ) async {
    final backend = _MeterBackend();
    await showApp(tester, backend);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    final startMeter = find.byKey(const Key('start-meter'));
    await tester.ensureVisible(startMeter);
    await tester.tap(startMeter);
    await tester.pump();
    final stopMeter = find.byKey(const Key('stop-meter'));
    await tester.ensureVisible(stopMeter);
    await tester.tap(stopMeter);
    await tester.pump();
    expect(backend.meterStops, 1);
    expect(backend.trialStarts, 0);
    expect(tester.takeException(), isNull);
  });
}
