import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import '../lib/calibration/read_bundle.dart';
import '../lib/calibration/tone_calibration.dart'
    show captureFingerprint, routeSignature;
import '../lib/domain/experiment.dart';
import '../lib/signal/analysis.dart';
import '../lib/signal/breathing.dart';
import '../lib/signal/synthesis.dart';

// Local WAV replay only. The three captures are a calibration set.
void main(List<String> args) {
  if (args.length != 5 || args[3] != '--out') {
    stderr.writeln(
      'Usage: dart tool/verify_breathing.dart STATIONARY.json MOTION.json OFF.json --out NEW_REPORT.json',
    );
    exitCode = 2;
    return;
  }
  final output = File(args[4]);
  if (output.existsSync() ||
      args.where((p) => p != '--out').any(FileSystemEntity.isLinkSync)) {
    throw StateError('Refusing symlink or existing output');
  }
  const conditions = [
    Scenario.stationary,
    Scenario.moving,
    Scenario.transmitterOff,
  ];
  final fingerprints = <String>{};
  final captures = <AudioCapture>[];
  final results = <AnalysisResult>[];
  final rows = <Map<String, Object?>>[];
  String? route, settings;
  for (var i = 0; i < conditions.length; i++) {
    final bundle =
        jsonDecode(File(args[i]).readAsStringSync()) as Map<String, dynamic>;
    final c = readPhysicalBundle(bundle, mode: ProbeMode.breathing);
    if (c.config.scenario != conditions[i])
      throw FormatException('Wrong trial condition in input ${i + 1}');
    final waveformSettings = jsonEncode(c.config.toJson()..remove('scenario'));
    route ??= routeSignature(c);
    settings ??= waveformSettings;
    if (routeSignature(c) != route || waveformSettings != settings) {
      throw StateError(
        'Calibration recordings must use the same waveform, echo window and input route',
      );
    }
    final fingerprint = captureFingerprint(c);
    if (!fingerprints.add(fingerprint))
      throw StateError('Reused calibration PCM');
    final expected = waveform(c.config);
    if (c.emitted.length != expected.length) {
      throw StateError('Emitted waveform length differs in input ${i + 1}');
    }
    for (var j = 0; j < expected.length; j++) {
      if (!c.emitted[j].isFinite || (c.emitted[j] - expected[j]).abs() > 1e-8) {
        throw StateError(
          'Emitted waveform differs from configuration in input ${i + 1}',
        );
      }
    }
    final r = analyze(c);
    captures.add(c);
    results.add(r);
    rows.add({
      'condition': conditions[i].name,
      'trialId': bundle['manifest']['trialId'],
      'sourceRevision': bundle['manifest']['sourceRevision'],
      'fingerprint': fingerprint,
      'startedUtc': c.startedUtc.toIso8601String(),
      'samples': c.received.length,
      'quality': r.quality,
      'analysis': r.settings,
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
  final report = {
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
  output.createSync(exclusive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}
