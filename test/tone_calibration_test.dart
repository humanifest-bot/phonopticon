import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/calibration/tone_calibration.dart';
import 'package:phonopticon/calibration/read_bundle.dart';
import 'package:phonopticon/domain/experiment.dart';
import 'package:phonopticon/export/artifacts.dart';
import 'package:phonopticon/signal/analysis.dart';
import 'package:phonopticon/signal/synthesis.dart';

// Synthetic acoustic fixtures labelled PHYSICAL only to exercise the contract.
// These tests never open a device and provide no hardware validation.
AudioCapture fixture(
  Scenario role, {
  int seed = 1,
  double gain = 1,
  bool quietMotion = false,
}) {
  final c = ExperimentConfig(scenario: role);
  final random = math.Random(seed);
  final rx = Float64List.fromList([
    for (var i = 0; i < c.samples; i++)
      gain *
          ((role == Scenario.transmitterOff
                  ? 0
                  : .004 * math.sin(2 * math.pi * 10000 * i / 48000)) +
              (role == Scenario.moving && !quietMotion
                  ? .001 * math.sin(2 * math.pi * 10020 * i / 48000)
                  : 0) +
              (random.nextDouble() - .5) * .00001),
  ]);
  return AudioCapture(
    config: c,
    emitted: waveform(c),
    received: rx,
    startedUtc: DateTime.utc(2026),
    sourceKind: 'PHYSICAL',
    backendId: 'test-only',
    deviceMetadata: {
      'inputLabel': 'synthetic test route',
      'inputSettings': {'sampleRate': 48000},
    },
  );
}

void main() {
  late ToneCalibration p;
  late AudioCapture stationary;
  setUpAll(() {
    stationary = fixture(Scenario.stationary);
    final moving = fixture(Scenario.moving, seed: 2),
        off = fixture(Scenario.transmitterOff, seed: 3);
    p = ToneCalibration.fit([
      for (final c in [stationary, moving, off])
        CalibrationObservation(c, analyze(c)),
    ]);
  });
  test(
    'independent Doppler sideband detected and stationary control stays low',
    () {
      final move = fixture(Scenario.moving, seed: 4),
          still = fixture(Scenario.stationary, seed: 5);
      expect(p.apply(move, analyze(move)).movementDetected, isTrue);
      expect(p.apply(still, analyze(still)).valid, isTrue);
      expect(p.apply(still, analyze(still)).movementDetected, isFalse);
    },
  );
  test(
    'received ratio is invariant to uniform input gain while carrier remains usable',
    () {
      final a = fixture(Scenario.moving, seed: 7),
          b = fixture(Scenario.moving, seed: 7, gain: 3);
      final x = p.apply(a, analyze(a)), y = p.apply(b, analyze(b));
      expect(
        x.settings['trialScore'],
        closeTo(y.settings['trialScore'] as double, 1e-8),
      );
      expect(y.movementDetected, isTrue);
    },
  );
  test(
    'off noise and weak tone give unavailable decisions, never huge-ratio movement',
    () {
      for (final c in [
        fixture(Scenario.transmitterOff, seed: 8),
        fixture(Scenario.moving, seed: 9, gain: .00001),
      ]) {
        final r = p.apply(c, analyze(c));
        expect(r.valid, isFalse);
        expect(r.movementDetected, isFalse);
        expect(r.quality.join(), contains('Probe absent'));
      }
    },
  );
  test(
    'calibration PCM reuse, malformed profile and changed route are rejected',
    () {
      expect(
        p.apply(stationary, analyze(stationary)).quality.join(),
        contains('held-out'),
      );
      expect(
        () => ToneCalibration.fromJson({...p.toJson(), 'threshold': 0}),
        throwsFormatException,
      );
      final c = fixture(Scenario.moving, seed: 10);
      final changed = AudioCapture(
        config: c.config,
        emitted: c.emitted,
        received: c.received,
        startedUtc: c.startedUtc,
        sourceKind: 'PHYSICAL',
        backendId: 'test-only',
        deviceMetadata: {'inputLabel': 'different'},
      );
      expect(
        p.apply(changed, analyze(changed)).quality.join(),
        contains('mismatch'),
      );
      expect(ToneCalibration.fromJson(p.toJson()).id, p.id);
    },
  );
  test(
    'overlapping calibration and absent carrier fail rather than force a threshold',
    () {
      final quiet = fixture(Scenario.moving, seed: 11, quietMotion: true),
          off = fixture(Scenario.transmitterOff, seed: 12);
      expect(
        () => ToneCalibration.fit([
          for (final c in [stationary, quiet, off])
            CalibrationObservation(c, analyze(c)),
        ]),
        throwsStateError,
      );
    },
  );
  test('decision is independent of supplied scenario label', () {
    final c = fixture(Scenario.moving, seed: 13);
    final relabelled = AudioCapture(
      config: const ExperimentConfig(scenario: Scenario.stationary),
      emitted: c.emitted,
      received: c.received,
      startedUtc: c.startedUtc,
      sourceKind: c.sourceKind,
      backendId: c.backendId,
      deviceMetadata: c.deviceMetadata,
    );
    expect(p.apply(relabelled, analyze(relabelled)).movementDetected, isTrue);
  });
  test(
    'physical WAV bundle can be independently decoded and calibration exported',
    () {
      final c = fixture(Scenario.moving, seed: 14);
      final r = p.apply(c, analyze(c));
      final bundle = artifactBundle(c, r);
      final decoded = readPhysicalBundle(bundle);
      expect(decoded.received.length, 192000);
      expect(decoded.received[1234], closeTo(c.received[1234], 1e-9));
      expect((bundle['manifest'] as Map)['physicalValidation'], isFalse);
      expect((bundle['manifest'] as Map)['calibrationProfile'], isNotNull);
    },
  );
}
