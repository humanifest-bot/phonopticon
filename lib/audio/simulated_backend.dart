import 'dart:typed_data';
import 'audio_backend.dart';
import '../domain/experiment.dart';
import '../signal/synthesis.dart';

class SimulatedBackend implements AudioBackend {
  SimulatedBackend({this.realtime = true});
  final bool realtime;
  bool _running = false, _stop = false, _disposed = false;
  @override
  AudioCapabilities get capabilities => const AudioCapabilities(
    'simulated-v1',
    'SIMULATED',
    true,
    'Deterministic PCM only. Does not access speakers or microphones.',
  );
  @override
  Future<AudioCapture> start(
    ExperimentConfig config, {
    void Function(double elapsed)? onProgress,
  }) async {
    config.validate();
    if (_disposed || _running)
      throw StateError('Backend unavailable or already running.');
    _running = true;
    _stop = false;
    final started = DateTime.now().toUtc(), watch = Stopwatch()..start();
    try {
      final steps = (config.durationSeconds * 20).ceil();
      var elapsed = 0.0;
      for (var i = 0; i < steps; i++) {
        await Future<void>.delayed(
          realtime ? const Duration(milliseconds: 50) : Duration.zero,
        );
        if (_stop) break;
        elapsed = ((i + 1) / 20).clamp(0, config.durationSeconds);
        onProgress?.call(elapsed);
      }
      if (_stop) {
        return AudioCapture(
          config: config,
          emitted: Float64List(0),
          received: Float64List(0),
          startedUtc: started,
          cancelled: true,
          elapsedMicroseconds: watch.elapsedMicroseconds,
          status: [
            'Cancelled before synthetic PCM generation; no estimate available.',
          ],
        );
      }
      final tx = waveform(config);
      final rx = synthesizeReceived(config, tx);
      return AudioCapture(
        config: config,
        emitted: tx,
        received: rx,
        startedUtc: started,
        elapsedMicroseconds: watch.elapsedMicroseconds,
      );
    } finally {
      _running = false;
      watch.stop();
    }
  }

  @override
  Future<void> stop() async {
    _stop = true;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _stop = true;
  }
}
