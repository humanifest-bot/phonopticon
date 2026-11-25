import 'dart:convert';
import 'dart:math' as math;
import '../domain/experiment.dart';
import '../signal/analysis.dart';
import '../signal/breathing.dart';
import '../signal/synthesis.dart';
import 'tone_calibration.dart' show captureFingerprint, routeSignature;

/// Recompute the fixed calibration criteria from three physical captures.
/// The inputs must be ordered stationary, moving, and transmitter-off.
Map<String, Object?> compareBreathingCaptures(
  List<AudioCapture> captures, {
  List<String?>? trialIds,
  List<String?>? sourceRevisions,
}) {
  const conditions = [
    Scenario.stationary,
    Scenario.moving,
    Scenario.transmitterOff,
  ];
  if (captures.length != conditions.length ||
      (trialIds != null && trialIds.length != conditions.length) ||
      (sourceRevisions != null &&
          sourceRevisions.length != conditions.length)) {
    throw FormatException(
      'Expected stationary, moving and transmitter-off captures',
    );
  }
  final fingerprints = <String>{};
  final results = <AnalysisResult>[];
  final rows = <Map<String, Object?>>[];
  String? route, settings;
  for (var i = 0; i < captures.length; i++) {
    final capture = captures[i];
    if (capture.sourceKind != 'PHYSICAL' ||
        capture.config.mode != ProbeMode.breathing ||
        capture.config.scenario != conditions[i]) {
      throw FormatException(
        'Wrong trial condition or source in input ${i + 1}',
      );
    }
    final waveformSettings = jsonEncode(
      capture.config.toJson()..remove('scenario'),
    );
    route ??= routeSignature(capture);
    settings ??= waveformSettings;
    if (routeSignature(capture) != route || waveformSettings != settings) {
      throw StateError(
        'Calibration recordings must use the same waveform, echo window and input route',
      );
    }
    final fingerprint = captureFingerprint(capture);
    if (!fingerprints.add(fingerprint)) {
      throw StateError('Reused calibration PCM');
    }
    final expected = waveform(capture.config);
    if (capture.emitted.length != expected.length) {
      throw StateError('Emitted waveform length differs in input ${i + 1}');
    }
    for (var j = 0; j < expected.length; j++) {
      if (!capture.emitted[j].isFinite ||
          (capture.emitted[j] - expected[j]).abs() > 1e-8) {
        throw StateError(
          'Emitted waveform differs from configuration in input ${i + 1}',
        );
      }
    }
    final result = analyze(capture);
    results.add(result);
    rows.add({
      'condition': conditions[i].name,
      'trialId': trialIds?[i],
      'sourceRevision': sourceRevisions?[i],
      'fingerprint': fingerprint,
      'startedUtc': capture.startedUtc.toIso8601String(),
      'samples': capture.received.length,
      'quality': result.quality,
      'analysis': result.settings,
    });
  }
  final still = results[0], move = results[1], off = results[2];
  const minimumRms = .001, minimumFraction = .25, rateToleranceHz = .05;
  double rms(AnalysisResult r) => (r.settings['periodicRms'] as double?) ?? 0;
  bool cadence(AnalysisResult r) =>
      r.valid &&
      (r.settings['periodicFraction'] as double) >= minimumFraction &&
      ((r.settings['peakHz'] as double) - ExperimentConfig.calibrationRhythmHz)
              .abs() <=
          rateToleranceHz + 1e-12;
  final threshold = math.max(minimumRms, 3 * rms(still));
  final stillQuiet =
      still.valid && !(cadence(still) && rms(still) >= minimumRms);
  final offRejected =
      off.quality.length == 1 &&
      off.quality.single == 'No coherent chirp probe found';
  final movingRecovered = cadence(move) && rms(move) >= threshold;
  return {
    'stage': 'physical calibration',
    'algorithm': breathingVersion,
    'expectedRhythmHz': ExperimentConfig.calibrationRhythmHz,
    'rateToleranceHz': rateToleranceHz,
    'minimumPeriodicFraction': minimumFraction,
    'periodicRmsThreshold': threshold,
    'config': captures.first.config.toJson()..remove('scenario'),
    'stationaryControlQuiet': stillQuiet,
    'offProbeRejected': offRejected,
    'movingCadenceRecovered': movingRecovered,
    'calibrationCriteriaMet': stillQuiet && offRejected && movingRecovered,
    'physicalValidation': false,
    'reference':
        'Operator paced movement. Displacement and timing are not independently measured.',
    'trials': rows,
  };
}
