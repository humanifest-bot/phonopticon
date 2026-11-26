import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/audio/audio_backend.dart';
import 'package:phonopticon/domain/experiment.dart';
import 'package:phonopticon/export/artifacts.dart';
import 'package:phonopticon/runner/trial_runner.dart';

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

  test(
    'partial microphone failure is retained and never accepted as a complete trial',
    () async {
      final runner = TrialRunner(_PartialInputBackend());
      await runner.start(const ExperimentConfig());
      expect(runner.state, TrialState.failed);
      expect(runner.capture, isNotNull);
      expect(runner.capture!.cancelled, isFalse);
      expect(runner.result!.valid, isFalse);
      expect(
        runner.result!.quality,
        contains(
          'Missing microphone input blocks; no physical analysis accepted.',
        ),
      );
      expect(runner.result!.quality, contains('Incomplete PCM'));

      final bundle = artifactBundle(
        runner.capture!,
        runner.result,
        trialId: 'partial-fixture',
      );
      final manifest = bundle['manifest'] as Map;
      final files = bundle['files'] as Map;
      final emitted = base64Decode(files['emitted.wav.base64'] as String);
      final received = base64Decode(files['received.wav.base64'] as String);
      expect(emitted.length, 44 + 3 * 4);
      expect(received.length, 44 + 3 * 4);
      expect(
        ByteData.sublistView(received).getFloat32(44, Endian.little),
        closeTo(.125, 1e-7),
      );
      expect(
        (manifest['deviceMetadata'] as Map)['emittedTail'],
        contains('Unknown'),
      );
      expect(
        manifest['status'],
        contains(
          'Missing microphone input blocks; no physical analysis accepted.',
        ),
      );
      await runner.dispose();
    },
  );
}

class _PartialInputBackend implements AudioBackend {
  @override
  AudioCapabilities get capabilities => const AudioCapabilities(
    'partial-fixture',
    'PHYSICAL',
    true,
    'fixture only',
  );

  @override
  Future<AudioCapture> start(
    ExperimentConfig config, {
    void Function(double)? onProgress,
  }) async => AudioCapture(
    config: config,
    emitted: Float64List.fromList([.01, .02, .01]),
    received: Float64List.fromList([.125, .25, .125]),
    startedUtc: DateTime.utc(2026),
    sourceKind: 'PHYSICAL',
    backendId: 'partial-fixture',
    status: const [
      'Missing microphone input blocks; no physical analysis accepted.',
    ],
    deviceMetadata: const {
      'emittedPrefixSamples': 3,
      'emittedTail': 'Unknown after reported prefix',
    },
  );

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
