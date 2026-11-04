import 'dart:convert';
import 'dart:io';
import '../lib/calibration/read_bundle.dart';
import '../lib/calibration/tone_calibration.dart';
import '../lib/signal/analysis.dart';

// Explicit local inputs/new output only. No playback, services or networking.
void main(List<String> args) {
  if (args.length < 5 || args[0] != 'fit' || args[1] != '--out') {
    stderr.writeln(
      'Usage: dart tool/calibrate_tone.dart fit --out NEW_PROFILE.json stationary.json moving.json off.json [more calibration bundles]',
    );
    exitCode = 2;
    return;
  }
  final output = File(args[2]);
  if (output.existsSync() || FileSystemEntity.isLinkSync(output.path)) {
    throw StateError('Output exists; calibration is never overwritten');
  }
  final observations = <CalibrationObservation>[];
  for (final path in args.skip(3)) {
    if (FileSystemEntity.isLinkSync(path))
      throw StateError('Symlink input rejected');
    final data =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final capture = readPhysicalBundle(data);
    observations.add(CalibrationObservation(capture, analyze(capture)));
  }
  final profile = ToneCalibration.fit(observations);
  output.createSync(exclusive: true);
  final file = output.openSync(mode: FileMode.writeOnly);
  try {
    file.writeStringSync(
      '${const JsonEncoder.withIndent('  ').convert(profile.toJson())}\n',
    );
  } finally {
    file.closeSync();
  }
  stdout.writeln(
    'Experimental calibration ${profile.id}: threshold=${profile.threshold}, carrierFloor=${profile.carrierFloor}, calibration counts=${profile.trainingCounts}. Held-out evaluation still required.',
  );
  stdout.writeln('Saved ${output.path}');
}
