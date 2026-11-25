import '../domain/experiment.dart';

class AudioCapabilities {
  const AudioCapabilities(
    this.id,
    this.sourceKind,
    this.available,
    this.description,
  );
  final String id, sourceKind, description;
  final bool available;
}

abstract interface class AudioBackend {
  AudioCapabilities get capabilities;
  Future<AudioCapture> start(
    ExperimentConfig config, {
    void Function(double elapsed)? onProgress,
  });
  Future<void> stop();
  Future<void> dispose();
}

/// Optional foreground microphone level check. No samples are retained.
abstract interface class MicrophoneMeterBackend {
  /// Completes when stopped, interrupted, or the bounded check expires.
  Future<void> startMeter({required void Function(double level) onLevel});
  Future<void> stopMeter();
}

class UnsupportedNativeBackend implements AudioBackend {
  @override
  AudioCapabilities get capabilities => const AudioCapabilities(
    'native-unimplemented',
    'PHYSICAL',
    false,
    'Native capture is not implemented. No microphone access or emission.',
  );
  @override
  Future<AudioCapture> start(
    ExperimentConfig config, {
    void Function(double elapsed)? onProgress,
  }) async => throw UnsupportedError(capabilities.description);
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
