import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import '../lib/audio/audio_backend.dart';
import '../lib/audio/simulated_backend.dart';
import '../lib/domain/experiment.dart';
import '../lib/runner/trial_runner.dart';
import '../lib/signal/analysis.dart';
import '../lib/signal/spectrum.dart';
import '../lib/signal/synthesis.dart';

var checks = 0;
void check(bool ok, String label) {
  if (!ok) throw StateError('FAIL: $label');
  checks++;
  stdout.writeln('PASS: $label');
}

AudioCapture fixture(ExperimentConfig c) {
  final tx = waveform(c);
  return AudioCapture(
    config: c,
    emitted: tx,
    received: synthesizeReceived(c, tx),
    startedUtc: DateTime.utc(2026, 10, 28),
  );
}

Future<void> main() async {
  final p = spectrum([
    for (var i = 0; i < 1024; i++) math.sin(2 * math.pi * 64 * i / 1024),
  ]);
  check(
    p.indexOf(p.reduce(math.max)) == 64 && (p[64] - 0.25).abs() < 0.001,
    'FFT known-bin sinusoid and power',
  );
  final c = const ExperimentConfig(mode: ProbeMode.chirp);
  final tx = waveform(c);
  check(
    tx.length == 192000 && tx.every((x) => x.abs() <= 0.02),
    'integer length and low amplitude',
  );
  check(
    (tx[2000] - tx[2960]).abs() < 1e-12,
    'whole chirps repeat without sample stretching',
  );
  check(
    interpolate(Float64List.fromList([0, 1, 0]), 0.5) == 0.5,
    'fractional delay interpolation',
  );
  for (final mode in ProbeMode.values) {
    for (final scenario in Scenario.values) {
      final config = ExperimentConfig(mode: mode, scenario: scenario);
      final audio = fixture(config), again = fixture(config);
      check(
        audio.received[10000] == again.received[10000],
        '${mode.name}/${scenario.name} deterministic PCM',
      );
      final result = analyze(audio);
      stdout.writeln(
        '  frames=${result.frames.length} peakMetric=${result.frames.fold<double>(0, (a, b) => math.max(a, b.movement))} detected=${result.movementDetected} quality=${result.quality}',
      );
      if (scenario == Scenario.invalid) {
        check(
          !result.valid && result.frames.isEmpty,
          '${mode.name} rejects invalid input',
        );
      } else if (scenario == Scenario.moving) {
        check(result.movementDetected, '${mode.name} moving fixture detected');
      } else {
        check(
          !result.movementDetected,
          '${mode.name}/${scenario.name} no movement detection',
        );
      }
      if (mode == ProbeMode.tone)
        check(
          result.frames.every((f) => f.range == null),
          'tone never invents range',
        );
    }
  }
  for (final range in [0.3, 0.5, 0.9, 1.0]) {
    final config = ExperimentConfig(
      mode: ProbeMode.chirp,
      scenario: Scenario.stationary,
      rangeMeters: range,
      startupSamples: 73,
    );
    final result = analyze(fixture(config));
    check(result.alignmentSamples == 73, 'PCM alignment at $range m');
    final estimates =
        result.frames.map((f) => f.range).whereType<double>().toList()..sort();
    check(
      estimates.isNotEmpty &&
          (estimates[estimates.length ~/ 2] - range).abs() <=
              result.nativeBinWidth + 343 / 96000,
      'range $range m within native-bin + delay quantization tolerance',
    );
  }
  final delayed = fixture(
    const ExperimentConfig(
      mode: ProbeMode.chirp,
      scenario: Scenario.stationary,
    ),
  );
  final synthetic = Float64List(delayed.emitted.length);
  // Independent sample-index echo. No range-to-delay function from the generator.
  for (var i = 140; i < synthetic.length; i++) {
    synthetic[i] = delayed.emitted[i] * 0.6 + delayed.emitted[i - 140] * 0.4;
  }
  final known = analyze(
    AudioCapture(
      config: delayed.config,
      emitted: delayed.emitted,
      received: synthetic,
      startedUtc: delayed.startedUtc,
    ),
  );
  final estimates =
      known.frames.map((f) => f.range).whereType<double>().toList()..sort();
  check(
    estimates.isNotEmpty &&
        (estimates[estimates.length ~/ 2] - 0.5002083333333334).abs() <
            known.nativeBinWidth,
    'independent 140-sample delay equals 0.500208 m',
  );
  final bad = fixture(const ExperimentConfig());
  bad.received[100] = 1.1;
  check(analyze(bad).quality.contains('Clipped PCM'), 'clipping rejected');
  var rejected = false;
  try {
    const ExperimentConfig(durationSeconds: 11).validate();
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'duration above ten seconds rejected');
  final runner = TrialRunner(SimulatedBackend(realtime: false));
  await runner.start(const ExperimentConfig(durationSeconds: 1));
  check(
    runner.state == TrialState.complete && runner.result != null,
    'runner completes analysis',
  );
  final pending = runner.start(const ExperimentConfig());
  var duplicateRejected = false;
  try {
    await runner.start(const ExperimentConfig());
  } catch (_) {
    duplicateRejected = true;
  }
  check(duplicateRejected, 'duplicate start rejected');
  await runner.stop();
  await pending;
  check(
    runner.state == TrialState.cancelled && runner.result == null,
    'stop cancels without stale result',
  );
  await runner.start(const ExperimentConfig(durationSeconds: 1));
  check(runner.state == TrialState.complete, 'restart after cancellation');
  await runner.dispose();
  var disposedRejected = false;
  try {
    await runner.start(const ExperimentConfig());
  } catch (_) {
    disposedRejected = true;
  }
  check(disposedRejected, 'disposed runner cannot start');
  final native = TrialRunner(UnsupportedNativeBackend());
  await native.start(const ExperimentConfig());
  check(
    native.state == TrialState.failed && native.capture == null,
    'native unavailable without simulation fallback',
  );
  await native.dispose();
  stdout.writeln('$checks checks passed. Synthetic evidence only.');
}
