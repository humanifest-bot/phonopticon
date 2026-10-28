import 'dart:math' as math;
import 'dart:typed_data';
import '../domain/experiment.dart';

// Fresh mathematical implementation; no upstream Python code is copied.
Float64List waveform(ExperimentConfig c) {
  c.validate();
  final out = Float64List(c.samples);
  if (!c.transmitterOn) return out;
  for (var i = 0; i < out.length; i++) {
    final t = i / c.sampleRate;
    final u = (i % c.sweepSamples) / c.sampleRate;
    final phase = c.mode == ProbeMode.tone
        ? c.toneHz * t
        : c.startHz * u + 0.5 * c.slope * u * u;
    final ramp = math.min(
      1.0,
      math.min(i, out.length - 1 - i) / (c.sampleRate * 0.01),
    );
    out[i] = c.amplitude * ramp * math.sin(2 * math.pi * phase);
  }
  return out;
}

// Stable LCG rather than platform-dependent Random implementation.
class SeededNoise {
  SeededNoise(int seed) : _state = seed & 0xffffffff;
  int _state;
  double next() {
    _state = (1664525 * _state + 1013904223) & 0xffffffff;
    return (_state / 4294967296.0) * 2 - 1;
  }
}

double interpolate(Float64List x, double index) {
  if (index < 0 || index >= x.length - 1) return 0;
  final i = index.floor();
  final f = index - i;
  return x[i] * (1 - f) + x[i + 1] * f;
}

Float64List synthesizeReceived(ExperimentConfig c, Float64List tx) {
  final noise = SeededNoise(c.seed);
  final rx = Float64List(tx.length);
  for (var i = 0; i < rx.length; i++) {
    final t = (i - c.startupSamples) / c.sampleRate;
    final moving =
        c.scenario == Scenario.moving || c.scenario == Scenario.transmitterOff;
    final r =
        c.rangeMeters +
        (moving ? c.motionMeters * math.sin(2 * math.pi * c.motionHz * t) : 0);
    final echoDelay = 2 * r / ExperimentConfig.soundSpeed * c.sampleRate;
    final staticDelay = 2 * 1.07 / ExperimentConfig.soundSpeed * c.sampleRate;
    rx[i] =
        0.6 * interpolate(tx, (i - c.startupSamples).toDouble()) +
        0.4 * interpolate(tx, i - c.startupSamples - echoDelay) +
        0.12 * interpolate(tx, i - c.startupSamples - staticDelay) +
        (c.scenario == Scenario.silence ? 0 : c.noiseAmplitude * noise.next());
  }
  if (c.scenario == Scenario.invalid) rx[rx.length ~/ 2] = double.nan;
  return rx;
}
