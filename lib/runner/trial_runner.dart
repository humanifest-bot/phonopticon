import '../audio/audio_backend.dart';
import '../domain/experiment.dart';
import '../signal/analysis.dart';

enum TrialState {
  idle,
  preparing,
  running,
  stopping,
  complete,
  cancelled,
  failed,
}

class TrialRunner {
  TrialRunner(this.backend);
  final AudioBackend backend;
  TrialState state = TrialState.idle;
  AudioCapture? capture;
  AnalysisResult? result;
  String? error;
  double elapsed = 0;
  void Function()? onChanged;
  bool _disposed = false;
  int _generation = 0;
  bool get busy =>
      state == TrialState.preparing ||
      state == TrialState.running ||
      state == TrialState.stopping;
  void _notify() {
    if (!_disposed) onChanged?.call();
  }

  Future<void> start(ExperimentConfig config) async {
    if (_disposed || busy) throw StateError('Runner is busy or disposed.');
    config.validate();
    final generation = ++_generation;
    capture = null;
    result = null;
    error = null;
    elapsed = 0;
    state = TrialState.preparing;
    _notify();
    try {
      if (!backend.capabilities.available)
        throw UnsupportedError(backend.capabilities.description);
      state = TrialState.running;
      _notify();
      final audio = await backend.start(
        config,
        onProgress: (value) {
          if (!_disposed && generation == _generation) {
            elapsed = value;
            _notify();
          }
        },
      );
      if (_disposed || generation != _generation) return;
      capture = audio;
      if (audio.cancelled || state == TrialState.stopping) {
        state = TrialState.cancelled;
      } else {
        result = analyze(audio);
        state = result!.valid ? TrialState.complete : TrialState.failed;
        if (!result!.valid) error = result!.quality.join('; ');
      }
    } catch (e) {
      if (_disposed || generation != _generation) return;
      error = e.toString();
      state = TrialState.failed;
    }
    _notify();
  }

  Future<void> stop() async {
    if (!busy || state == TrialState.stopping) return;
    state = TrialState.stopping;
    _notify();
    await backend.stop();
  }

  Future<void> dispose() async {
    _disposed = true;
    ++_generation;
    onChanged = null;
    await backend.dispose();
  }
}
