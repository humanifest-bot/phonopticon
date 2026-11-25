import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/calibration/breathing_comparison.dart';
import 'package:phonopticon/domain/experiment.dart';
import 'package:phonopticon/signal/synthesis.dart';

AudioCapture fixture(Scenario condition, {String route = 'fixture-mic'}) {
  final config = ExperimentConfig(
    mode: ProbeMode.breathing,
    scenario: condition,
    durationSeconds: 30,
    rangeMeters: .56,
    breathingGateMeters: .6,
    motionMeters: .004,
    motionHz: .25,
    startupSamples: 1307,
    noiseAmplitude: .0003,
  );
  final emitted = waveform(config);
  return AudioCapture(
    config: config,
    emitted: emitted,
    received: synthesizeReceived(config, emitted),
    startedUtc: DateTime.utc(2026),
    sourceKind: 'PHYSICAL', // Mock metadata to exercise the physical contract.
    backendId: 'fixture-only',
    deviceMetadata: {'inputLabel': route},
  );
}

void main() {
  test('fixed criteria distinguish matching controls and reject mismatch', () {
    final stationary = fixture(Scenario.stationary);
    final moving = fixture(Scenario.moving);
    final off = fixture(Scenario.transmitterOff);
    final captures = [stationary, moving, off];
    final report = compareBreathingCaptures(
      captures,
      trialIds: ['still', 'move', 'off'],
      sourceRevisions: ['fixture', 'fixture', 'fixture'],
    );
    expect(report['stationaryControlQuiet'], isTrue);
    expect(report['offProbeRejected'], isTrue);
    expect(report['movingCadenceRecovered'], isTrue);
    expect(report['calibrationCriteriaMet'], isTrue);
    expect(report['physicalValidation'], isFalse);
    expect(report['minimumPeriodicFraction'], .25);
    expect((report['trials'] as List)[1]['trialId'], 'move');
    expect(
      () => compareBreathingCaptures([moving, stationary, off]),
      throwsFormatException,
    );
    expect(
      () => compareBreathingCaptures([
        stationary,
        fixture(Scenario.moving, route: 'different-mic'),
        off,
      ]),
      throwsStateError,
    );
    final duplicate = AudioCapture(
      config: moving.config,
      emitted: moving.emitted,
      received: stationary.received,
      startedUtc: DateTime.utc(2026),
      sourceKind: 'PHYSICAL',
      backendId: 'fixture-only',
      deviceMetadata: {'inputLabel': 'fixture-mic'},
    );
    expect(
      () => compareBreathingCaptures([stationary, duplicate, off]),
      throwsStateError,
    );
    final corrupted = Float64List.fromList(off.emitted)..[100] = .1;
    final alteredOff = AudioCapture(
      config: off.config,
      emitted: corrupted,
      received: off.received,
      startedUtc: DateTime.utc(2026),
      sourceKind: 'PHYSICAL',
      backendId: 'fixture-only',
      deviceMetadata: {'inputLabel': 'fixture-mic'},
    );
    expect(
      () => compareBreathingCaptures([stationary, moving, alteredOff]),
      throwsStateError,
    );
  });
}
