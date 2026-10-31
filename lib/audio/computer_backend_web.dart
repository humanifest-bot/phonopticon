import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'audio_backend.dart';
import '../domain/experiment.dart';
import '../signal/synthesis.dart';

@JS('phonopticonAudio.available')
external bool get _available;
@JS('phonopticonAudio.start')
external JSPromise<JSString> _start(JSString config, JSFloat32Array waveform);
@JS('phonopticonAudio.stop')
external void _stop();
@JS('phonopticonAudio.elapsed')
external double get _elapsed;

bool computerBackendAvailable() {
  try {
    return _available;
  } catch (_) {
    return false;
  }
}

AudioBackend createComputerBackend() => ComputerBackend();

class ComputerBackend implements AudioBackend {
  bool _disposed = false;
  @override
  AudioCapabilities get capabilities => AudioCapabilities(
    'browser-audio-v1',
    'PHYSICAL',
    computerBackendAvailable(),
    'Experimental local microphone and speaker capture. Permission and explicit Start required.',
  );
  @override
  Future<AudioCapture> start(
    ExperimentConfig config, {
    void Function(double elapsed)? onProgress,
  }) async {
    config.validate();
    if (_disposed) throw StateError('Backend disposed');
    final tx = waveform(config);
    final watch = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => onProgress?.call(_elapsed),
    );
    try {
      final json = (await _start(
        jsonEncode(config.toJson()).toJS,
        Float32List.fromList(tx).toJS,
      ).toDart).toDart;
      final data = jsonDecode(json) as Map<String, dynamic>;
      final rx = Float64List.fromList(
        (data['samples'] as List).map((x) => (x as num).toDouble()).toList(),
      );
      return AudioCapture(
        config: config,
        emitted: tx,
        received: rx,
        sourceKind: 'PHYSICAL',
        backendId: 'browser-audio-v1',
        startedUtc: DateTime.parse(data['startedUtc'] as String),
        elapsedMicroseconds: data['elapsedMicroseconds'] as int,
        actualSampleRate: data['actualSampleRate'] as int,
        deviceMetadata: Map<String, Object?>.from(data['metadata'] as Map),
        cancelled: data['cancelled'] as bool,
      );
    } finally {
      watch.cancel();
    }
  }

  @override
  Future<void> stop() async => _stop();
  @override
  Future<void> dispose() async {
    _disposed = true;
    _stop();
  }
}
