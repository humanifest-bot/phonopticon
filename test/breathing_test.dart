import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/domain/experiment.dart';
import 'package:phonopticon/signal/analysis.dart';
import 'package:phonopticon/signal/synthesis.dart';

void main() {
  test(
    'FMCW recovers slow millimeter-scale fixture motion with both controls',
    () {
      AnalysisResult run(Scenario condition) {
        final config = ExperimentConfig(
          mode: ProbeMode.breathing,
          scenario: condition,
          durationSeconds: 30,
          rangeMeters: .56,
          breathingGateMeters: .6,
          motionMeters: .004,
          motionHz: .25,
          startupSamples: 1307, // A physical delay can exceed one chirp period.
          noiseAmplitude: .0003,
        );
        final emitted = waveform(config);
        return analyze(
          AudioCapture(
            config: config,
            emitted: emitted,
            received: synthesizeReceived(config, emitted),
            startedUtc: DateTime.utc(2026),
          ),
        );
      }

      final stationary = run(Scenario.stationary);
      final moving = run(Scenario.moving);
      final off = run(Scenario.transmitterOff);
      expect(stationary.quality, isEmpty);
      expect(moving.quality, isEmpty);
      expect(moving.settings['peakHz'], closeTo(.25, .02));
      expect(moving.settings['periodicFraction'], greaterThan(.25));
      expect(moving.settings['periodicRms'], greaterThan(.001));
      expect(stationary.settings['periodicRms'], lessThan(.001));
      expect(off.quality, ['No coherent chirp probe found']);
      expect(off.settings.containsKey('peakHz'), isFalse);
    },
  );
}
