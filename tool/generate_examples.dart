import 'dart:convert';
import 'dart:io';
import '../lib/domain/experiment.dart';
import '../lib/export/artifacts.dart';
import '../lib/signal/analysis.dart';
import '../lib/signal/synthesis.dart';

void main(List<String> args) {
  if (args.length != 2 || args[0] != '--out') {
    stderr.writeln(
      'Usage: dart tool/generate_examples.dart --out NEW_DIRECTORY',
    );
    exitCode = 64;
    return;
  }
  final dir = Directory(args[1]);
  if (dir.existsSync()) {
    throw StateError('Output directory must not exist; no overwrites.');
  }
  dir.createSync(recursive: true);
  final summaries = <Map<String, Object?>>[];
  final configurations = <Map<String, Object>>[];
  for (final mode in ProbeMode.values) {
    for (final scenario in [
      Scenario.stationary,
      Scenario.moving,
      Scenario.transmitterOff,
      Scenario.invalid,
    ]) {
      final c = ExperimentConfig(
        mode: mode,
        scenario: scenario,
        durationSeconds: 2,
        seed: 99,
      );
      final tx = waveform(c);
      final audio = AudioCapture(
        config: c,
        emitted: tx,
        received: synthesizeReceived(c, tx),
        startedUtc: DateTime.utc(2026, 10, 28),
      );
      final result = analyze(audio), id = '${mode.name}-${scenario.name}';
      final bundle = artifactBundle(audio, result, trialId: id);
      File('${dir.path}/$id.json').writeAsStringSync(jsonEncode(bundle));
      final estimates =
          result.frames.map((f) => f.range).whereType<double>().toList()
            ..sort();
      final median = estimates.isEmpty
          ? null
          : estimates[estimates.length ~/ 2];
      final scores = result.frames.map((f) => f.movement).toList()..sort();
      summaries.add({
        'trial': id,
        'sourceKind': 'SIMULATED',
        'frames': result.frames.length,
        'movementDetected': result.movementDetected,
        'quality': result.quality,
        'peakMetric': scores.isEmpty ? null : scores.last,
        'medianEquivalentRangeMeters': median,
        'stationaryRangeErrorMeters':
            scenario == Scenario.stationary && median != null
            ? (median - c.rangeMeters).abs()
            : null,
        'nativeBinWidth': result.nativeBinWidth,
        'pcmFingerprints': (bundle['manifest'] as Map)['fingerprints'],
      });
      configurations.add({'trial': id, ...c.toJson()});
    }
  }
  const encoder = JsonEncoder.withIndent('  ');
  File(
    '${dir.path}/summary.json',
  ).writeAsStringSync('${encoder.convert(summaries)}\n');
  File(
    '${dir.path}/configurations.json',
  ).writeAsStringSync('${encoder.convert(configurations)}\n');
  stdout.writeln(
    'Generated ${summaries.length} simulated bundles in ${dir.path}',
  );
}
