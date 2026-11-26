import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/domain/experiment.dart';
import 'package:phonopticon/ui/recording_diagnostics.dart';

AudioCapture capture(
  Float64List samples, {
  Scenario scenario = Scenario.transmitterOff,
}) => AudioCapture(
  config: ExperimentConfig(mode: ProbeMode.breathing, scenario: scenario),
  emitted: Float64List(samples.length),
  received: samples,
  startedUtc: DateTime.utc(2026),
  sourceKind: 'PHYSICAL',
);

AnalysisResult result({
  List<AnalysisFrame> frames = const [],
  List<String> quality = const [],
  Map<String, Object?> settings = const {},
}) => AnalysisResult(
  axis: const [],
  frames: frames,
  quality: quality,
  settings: settings,
  axisLabel: '',
  threshold: 0,
);

void main() {
  test(
    'detects exact silence and clipping without claiming silence is ambient noise',
    () {
      final silent = summarizeRecording(capture(Float64List(4800)));
      expect(silent.exactlySilent, isTrue);
      expect(silent.probeBandFraction, isNull);
      expect(silent.clippedSamples, 0);
      final samples = Float64List(4800)
        ..[30] = 1
        ..[31] = -1;
      final clipped = summarizeRecording(capture(samples));
      expect(clipped.exactlySilent, isFalse);
      expect(clipped.clippedSamples, 2);
      expect(clipped.rms, closeTo(math.sqrt(2 / 4800), 1e-10));
    },
  );

  test(
    'distinguishes in-band from out-of-band sound and flags a timed transient',
    () {
      Float64List tone(double hz) => Float64List.fromList([
        for (var i = 0; i < 96000; i++)
          .001 * math.sin(2 * math.pi * hz * i / 48000),
      ]);
      final inBand = tone(5000);
      final outside = tone(1000);
      for (var i = 60000; i < 64800; i++) {
        inBand[i] += .05 * math.sin(2 * math.pi * 5000 * i / 48000);
      }
      final insideSummary = summarizeRecording(capture(inBand));
      final outsideSummary = summarizeRecording(capture(outside));
      expect(insideSummary.probeBandFraction!, greaterThan(.7));
      expect(outsideSummary.probeBandFraction!, lessThan(.01));
      expect(insideSummary.transientsSeconds, contains(closeTo(1.25, .06)));
      expect(outsideSummary.transientsSeconds, isEmpty);
      expect(insideSummary.transmitterOn, isFalse);
    },
  );

  test('preserves analysis alignment and handles invalid input explicitly', () {
    final samples = Float64List(4800)..[0] = double.nan;
    final summary = summarizeRecording(
      capture(samples),
      analysis: result(
        settings: {
          'probeMatchStart': .9,
          'probeMatchEnd': .8,
          'startLagSamples': 8,
          'endLagSamples': 9,
        },
      ),
    );
    expect(summary.nonFiniteSamples, 1);
    expect(summary.exactlySilent, isFalse);
    expect(summary.probeMatchStart, .9);
    expect(summary.endLagSamples, 9);
  });

  testWidgets(
    'quiet inputs stay distinguishable and rejected alignment stays tentative',
    (tester) async {
      final quiet = Float64List.fromList([
        for (var i = 0; i < 4800; i++)
          .00001 * math.sin(2 * math.pi * 5000 * i / 48000),
      ]);
      final summary = summarizeRecording(
        capture(quiet),
        analysis: result(
          quality: const ['No coherent chirp probe found'],
          settings: const {
            'probeMatchFloor': .3,
            'probeMatchStart': .1,
            'probeMatchEnd': .1,
            'startLagSamples': 7,
            'endLagSamples': 8,
          },
        ),
      );
      expect(summary.reliableAlignment, isFalse);
      expect(summary.rms, greaterThan(0));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordingDiagnosticsPanel(
                summary: summary,
                label: 'fixture-id',
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('fixture-id'), findsOneWidget);
      expect(find.textContaining('No reliable alignment'), findsOneWidget);
      expect(find.textContaining('RMS 0.000 full scale'), findsNothing);
    },
  );

  testWidgets(
    'comparison names unavailable off trace and non-synchronized axes',
    (tester) async {
      final comparison = alignTrialTraces({
        'Stationary': result(
          frames: const [
            AnalysisFrame(1, [], .1, null),
            AnalysisFrame(2, [], -.2, null),
          ],
          settings: {'traceGateMeters': .6, 'traceComponent': 'I'},
        ),
        'Transmitter off': result(
          quality: const ['No coherent chirp probe found'],
        ),
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TrialTraceComparisonPanel(comparison: comparison),
            ),
          ),
        ),
      );
      expect(find.textContaining('not synchronized'), findsOneWidget);
      expect(
        find.textContaining('Transmitter off: trace unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('gate 0.6 m, component I'), findsOneWidget);
      expect(find.textContaining('vertical scale: ±0.222'), findsOneWidget);
    },
  );
}
