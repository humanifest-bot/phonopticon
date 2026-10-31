import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/domain/experiment.dart';
import 'package:phonopticon/export/artifacts.dart';

void main() {
  test(
    'physical-labelled mock export never inherits simulated source claims',
    () {
      // Schema fixture only, not a real microphone recording.
      final capture = AudioCapture(
        config: const ExperimentConfig(),
        emitted: Float64List(16),
        received: Float64List(16),
        startedUtc: DateTime.utc(2026),
        sourceKind: 'PHYSICAL',
        backendId: 'mock-physical-schema',
        deviceMetadata: {'fixtureOnly': true, 'audioContextRate': 48000},
      );
      final bundle = artifactBundle(capture, null);
      final manifest = bundle['manifest'] as Map;
      final config = manifest['config'] as Map;
      final files = bundle['files'] as Map;
      expect(manifest['physicalValidation'], false);
      expect(manifest['fixtureModel'], isNull);
      expect(config.containsKey('rangeMeters'), false);
      expect(config.containsKey('seed'), false);
      expect((manifest['waveform'] as Map).containsKey('directGain'), false);
      expect(files['movement.svg'], contains('PHYSICAL'));
      expect(files['spectrum.svg'], isNot(contains('SIMULATED')));
      expect(manifest['calibration'], contains('uncalibrated'));
    },
  );
}
