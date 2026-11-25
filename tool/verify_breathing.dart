import 'dart:convert';
import 'dart:io';
import '../lib/calibration/breathing_comparison.dart';
import '../lib/calibration/read_bundle.dart';
import '../lib/domain/experiment.dart';

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
  final bundles = [
    for (var i = 0; i < 3; i++)
      jsonDecode(File(args[i]).readAsStringSync()) as Map<String, dynamic>,
  ];
  final report = compareBreathingCaptures(
    [
      for (final bundle in bundles)
        readPhysicalBundle(bundle, mode: ProbeMode.breathing),
    ],
    trialIds: [
      for (final bundle in bundles) bundle['manifest']['trialId'] as String?,
    ],
    sourceRevisions: [
      for (final bundle in bundles)
        bundle['manifest']['sourceRevision'] as String?,
    ],
  );
  output.createSync(exclusive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}
