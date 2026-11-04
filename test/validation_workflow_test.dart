import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/audio/audio_backend.dart';
import 'package:phonopticon/calibration/tone_calibration.dart';
import 'package:phonopticon/domain/experiment.dart';
import 'package:phonopticon/main.dart';
import 'package:phonopticon/signal/synthesis.dart';

class MockPhysicalBackend implements AudioBackend {
  int starts = 0;
  @override
  AudioCapabilities get capabilities =>
      const AudioCapabilities('workflow-mock', 'PHYSICAL', true, 'test only');
  @override
  Future<AudioCapture> start(
    ExperimentConfig c, {
    void Function(double)? onProgress,
  }) async {
    starts++;
    return AudioCapture(
      config: c,
      emitted: waveform(c),
      received: Float64List.fromList([
        for (var i = 0; i < c.samples; i++)
          c.transmitterOn
              ? .004 * math.sin(2 * math.pi * 10000 * i / 48000)
              : 0,
      ]),
      startedUtc: DateTime.utc(2026),
      sourceKind: 'PHYSICAL',
      backendId: 'workflow-mock',
      deviceMetadata: const {},
    );
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets(
    'validation requires manual Start and Next, locks settings, and retains one slot per attempt',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = MockPhysicalBackend();
      final template = AudioCapture(
        config: const ExperimentConfig(),
        emitted: Float64List(0),
        received: Float64List(0),
        startedUtc: DateTime.utc(2026),
        sourceKind: 'PHYSICAL',
        backendId: 'workflow-mock',
        deviceMetadata: const {},
      );
      final p = ToneCalibration(
        id: 'test-only',
        sampleRate: 48000,
        toneHz: 10000,
        amplitude: .02,
        durationSeconds: 4,
        route: routeSignature(template),
        carrierFloor: 1e-9,
        threshold: .003,
        trainingFingerprints: const ['a', 'b', 'c'],
        trainingCounts: const {'stationary': 1, 'moving': 1, 'off': 1},
      );
      await tester.pumpWidget(
        PhonopticonApp(backend: backend, initialCalibration: p),
      );
      await tester.tap(find.byKey(const Key('begin-validation')));
      await tester.pumpAndSettle();
      expect(backend.starts, 0);
      expect(find.textContaining('Validation 0/15 saved'), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<ProbeMode>>(
              find.byType(SegmentedButton<ProbeMode>),
            )
            .onSelectionChanged,
        isNull,
      );
      await tester.ensureVisible(find.byKey(const Key('start')));
      await tester.tap(find.byKey(const Key('start')));
      await tester.pumpAndSettle();
      expect(backend.starts, 1);
      expect(find.textContaining('Validation 1/15 saved'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('start'))).onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byKey(const Key('next-validation')));
      await tester.tap(find.byKey(const Key('next-validation')));
      await tester.pumpAndSettle();
      expect(backend.starts, 1);
      expect(find.textContaining('Validation 1/15 saved'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('start'))).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
