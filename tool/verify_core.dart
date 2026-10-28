import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import '../lib/audio/audio_backend.dart';
import '../lib/export/artifacts.dart';
import 'dart:convert';
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
  for (final velocity in [-0.15, 0.15]) {
    final config = const ExperimentConfig(durationSeconds: 2);
    final emitted = waveform(config);
    final doppler = 2 * velocity * 10000 / 343;
    final rx = Float64List.fromList([
      for (var i = 0; i < config.samples; i++)
        0.012 * math.sin(2 * math.pi * 10000 * i / 48000) +
            0.008 * math.sin(2 * math.pi * (10000 + doppler) * i / 48000),
    ]);
    final result = analyze(
      AudioCapture(
        config: config,
        emitted: emitted,
        received: rx,
        startedUtc: DateTime.utc(2026),
      ),
    );
    final frame = result.frames[result.frames.length ~/ 2];
    var peak = -1;
    for (var i = 0; i < result.axis.length; i++) {
      if (result.axis[i].abs() >= 6 &&
          (peak < 0 || frame.power[i] > frame.power[peak]))
        peak = i;
    }
    check(
      (result.axis[peak] - doppler).abs() <= result.nativeBinWidth,
      'independent signed Doppler at velocity $velocity m/s',
    );
  }
  for (final mode in ProbeMode.values) {
    for (final seed in [17, 99]) {
      for (final near in [false, true]) {
        final config = ExperimentConfig(
          mode: mode,
          seed: seed,
          toneHz: near ? 19000 : 10000,
          startHz: near ? 18000 : 3000,
          endHz: near ? 20000 : 10000,
        );
        check(
          analyze(fixture(config)).movementDetected,
          '${mode.name} held-out seed $seed near=$near movement',
        );
      }
    }
  }
  final exported = fixture(const ExperimentConfig());
  final bundle = artifactBundle(
    exported,
    analyze(exported),
    trialId: 'fixed-test',
  );
  final decoded = jsonDecode(jsonEncode(bundle)) as Map<String, dynamic>;
  final wav = base64Decode(decoded['files']['received.wav.base64'] as String);
  final header = ByteData.sublistView(wav);
  check(
    ascii.decode(wav.sublist(0, 4)) == 'RIFF' &&
        header.getUint16(20, Endian.little) == 3 &&
        header.getUint32(24, Endian.little) == 48000 &&
        header.getUint32(40, Endian.little) == 192000 * 4,
    'exported WAV format and sample length',
  );
  check(
    (header.getFloat32(44 + 10000 * 4, Endian.little) -
                exported.received[10000])
            .abs() <
        1e-8,
    'export preserves raw PCM within Float32 precision',
  );
  check(
    fingerprint(utf8.encode('hello')) == '4f9f2cab',
    'FNV fingerprint independent known vector',
  );
  check(
    decoded['manifest']['sourceKind'] == 'SIMULATED' &&
        decoded['manifest']['physicalValidation'] == false &&
        decoded['analysis']['frames'].isNotEmpty &&
        (decoded['files']['metrics.csv'] as String).startsWith(
          'seconds,movement',
        ),
    'export includes source, configuration, arrays and metrics',
  );
  check(
    (decoded['files']['movement.svg'] as String).contains('<svg') &&
        (decoded['files']['spectrum.svg'] as String).contains('SIMULATED'),
    'standalone labelled SVG exports',
  );
  final driftReference = fixture(const ExperimentConfig(mode: ProbeMode.chirp));
  final drifted = Float64List(driftReference.received.length);
  for (var i = 0; i < drifted.length; i++) {
    drifted[i] = interpolate(
      driftReference.received,
      i - 4 * i / drifted.length,
    );
  }
  final driftResult = analyze(
    AudioCapture(
      config: driftReference.config,
      emitted: driftReference.emitted,
      received: drifted,
      startedUtc: driftReference.startedUtc,
    ),
  );
  check(
    !driftResult.valid && driftResult.quality.join().contains('drift'),
    'timing drift rejects dependent ranging',
  );
  final mismatch = AudioCapture(
    config: driftReference.config,
    emitted: driftReference.emitted,
    received: driftReference.received,
    actualSampleRate: 44100,
    startedUtc: driftReference.startedUtc,
  );
  check(
    !analyze(mismatch).valid,
    'actual/requested sample-rate mismatch rejected',
  );
  final mismatchBundle = artifactBundle(mismatch, analyze(mismatch));
  final mismatchManifest = mismatchBundle['manifest'] as Map;
  check(
    (mismatchManifest['actualAudioFormat'] as Map)['sampleRate'] == 44100,
    'export preserves actual capture rate instead of requested rate',
  );
  final before = analyze(driftReference);
  final truthChanged = analyze(
    AudioCapture(
      config: const ExperimentConfig(mode: ProbeMode.chirp, rangeMeters: 0.9),
      emitted: driftReference.emitted,
      received: driftReference.received,
      startedUtc: driftReference.startedUtc,
    ),
  );
  check(
    before.frames.first.range == truthChanged.frames.first.range &&
        before.frames.first.movement == truthChanged.frames.first.movement,
    'estimator ignores synthetic reflector truth',
  );
  for (final delay in [20, 400]) {
    final clean = fixture(
      const ExperimentConfig(
        mode: ProbeMode.chirp,
        scenario: Scenario.stationary,
      ),
    );
    final rx = Float64List(clean.emitted.length);
    for (var i = delay; i < rx.length; i++) {
      rx[i] = 0.6 * clean.emitted[i] + 0.4 * clean.emitted[i - delay];
    }
    final result = analyze(
      AudioCapture(
        config: clean.config,
        emitted: clean.emitted,
        received: rx,
        startedUtc: clean.startedUtc,
      ),
    );
    check(
      result.frames.every((f) => f.range == null),
      'out-of-gate echo delay $delay has no confident range',
    );
  }
  var aliasRejected = false;
  try {
    const ExperimentConfig(mode: ProbeMode.chirp, sampleRate: 22050).validate();
  } catch (_) {
    aliasRejected = true;
  }
  check(aliasRejected, 'mixer sum alias overlap rejected');
  final broken = Float64List(driftReference.received.length);
  for (var i = 0; i < broken.length; i++) {
    broken[i] = interpolate(
      driftReference.received,
      (i - (i > broken.length ~/ 2 ? 5 : 0)).toDouble(),
    );
  }
  check(
    !analyze(
      AudioCapture(
        config: driftReference.config,
        emitted: driftReference.emitted,
        received: broken,
        startedUtc: driftReference.startedUtc,
      ),
    ).valid,
    'sample discontinuity invalidates ranging',
  );
  final preparing = TrialRunner(SimulatedBackend(realtime: false));
  preparing.onChanged = () {
    if (preparing.state == TrialState.preparing) preparing.stop();
  };
  await preparing.start(const ExperimentConfig());
  check(
    preparing.state == TrialState.cancelled && preparing.capture == null,
    'stop during preparation does not start backend',
  );
  await preparing.dispose();
  final maximum = TrialRunner(SimulatedBackend(realtime: false));
  await maximum.start(const ExperimentConfig(durationSeconds: 10));
  check(
    maximum.elapsed == 10 && maximum.capture!.received.length == 480000,
    'ten-second maximum completes with exact PCM length',
  );
  await maximum.dispose();
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
