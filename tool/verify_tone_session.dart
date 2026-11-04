import 'dart:convert';
import 'dart:io';
import '../lib/calibration/read_bundle.dart';
import '../lib/calibration/tone_calibration.dart';
import '../lib/signal/analysis.dart';

// Recompute every captured trial from its raw WAV, never from its verdict label.
void main(List<String> args) {
  if (args.length != 3 || args[1] != '--out') {
    stderr.writeln(
      'Usage: dart tool/verify_tone_session.dart SESSION.json --out NEW_REPORT.json',
    );
    exitCode = 2;
    return;
  }
  if (FileSystemEntity.isLinkSync(args[0]) ||
      FileSystemEntity.isLinkSync(args[2]) ||
      File(args[2]).existsSync()) {
    throw StateError('Refusing symlink input/output or existing output');
  }
  final session =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  if (session['kind'] != 'tone-held-out-validation' ||
      session['schemaVersion'] != 1) {
    throw FormatException('Expected validation session');
  }
  final p = ToneCalibration.fromJson(
    session['profile'] as Map<String, dynamic>,
  );
  final plan = (session['protocol']['order'] as List).cast<String>();
  final trials = session['trials'] as List;
  if (plan.length != 15 ||
      [
        'stationary',
        'moving',
        'transmitterOff',
      ].any((s) => plan.where((x) => x == s).length != 5) ||
      trials.length > 15) {
    throw FormatException('Invalid predeclared trial counts');
  }
  var movingHits = 0,
      stationaryFlags = 0,
      offFlags = 0,
      availableOn = 0,
      validCaptures = 0,
      expectedOffRejections = 0;
  final seen = <String>{}, rows = <Map<String, Object?>>[];
  for (var i = 0; i < trials.length; i++) {
    final item = trials[i] as Map;
    if (item['index'] != i + 1 || item['expectedCondition'] != plan[i])
      throw FormatException('Trial order mismatch');
    final bundle = item['bundle'];
    if (bundle == null) {
      rows.add({
        'index': i + 1,
        'condition': plan[i],
        'failure': item['error'],
        'decision': 'unavailable',
      });
      continue;
    }
    if (jsonEncode(bundle['manifest']['calibrationProfile']) !=
        jsonEncode(p.toJson())) {
      throw StateError('Trial uses a different calibration profile');
    }
    final c = readPhysicalBundle(Map<String, dynamic>.from(bundle));
    if (c.config.scenario.name != plan[i])
      throw StateError('Capture condition/order mismatch');
    if (!seen.add(captureFingerprint(c)))
      throw StateError('Repeated validation PCM');
    if (plan[i] == 'transmitterOff' && c.emitted.any((x) => x != 0))
      throw StateError('Off trial emitted a nonzero waveform');
    final raw = analyze(c);
    final result = p.apply(c, raw);
    if (raw.valid) validCaptures++;
    if (plan[i] != 'transmitterOff' && result.valid) availableOn++;
    if (result.movementDetected) {
      if (plan[i] == 'moving') movingHits++;
      if (plan[i] == 'stationary') stationaryFlags++;
      if (plan[i] == 'transmitterOff') offFlags++;
    }
    if (plan[i] == 'transmitterOff' &&
        raw.valid &&
        result.quality.length == 1 &&
        result.quality.single.startsWith('Probe absent'))
      expectedOffRejections++;
    rows.add({
      'index': i + 1,
      'condition': plan[i],
      'sourceRevision': bundle['manifest']['sourceRevision'],
      'rawValid': raw.valid,
      'cancelled': c.cancelled,
      'quality': result.quality,
      'score': result.settings['trialScore'],
      'carrierFraction': result.settings['carrierFraction'],
      'decision': !result.valid
          ? 'unavailable'
          : result.movementDetected
          ? 'movement'
          : 'no movement',
      'fingerprint': captureFingerprint(c),
    });
  }
  final complete = trials.length == 15 && session['completedTrials'] == 15;
  final summary = {
    'complete': complete,
    'plannedPerCondition': 5,
    'attempts': trials.length,
    'validRawCaptures': validCaptures,
    'availableTransmitterOnDecisions': availableOn,
    'movingHits': movingHits,
    'movingMissesOrUnavailable': 5 - movingHits,
    'stationaryFalseFlags': stationaryFlags,
    'offFalseFlags': offFlags,
    'offProbeAbsentRejections': expectedOffRejections,
    'threshold': p.threshold,
    'profileId': p.id,
    'localFeasibilityTargetMet':
        complete &&
        validCaptures == 15 &&
        availableOn == 10 &&
        movingHits >= 4 &&
        stationaryFlags + offFlags <= 1,
    'interpretation':
        'Small single-session feasibility only. Probe-absent decisions are unavailable, not proven stationary negatives. Do not tune on this evaluation set.',
    'trials': rows,
  };
  final output = File(args[2])..createSync(exclusive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(summary)}\n',
  );
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({...summary}..remove('trials')),
  );
}
