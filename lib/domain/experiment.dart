import 'dart:typed_data';

enum ProbeMode { tone, chirp }

enum Scenario { stationary, moving, transmitterOff, silence, invalid }

class ExperimentConfig {
  const ExperimentConfig({
    this.mode = ProbeMode.tone,
    this.scenario = Scenario.moving,
    this.sampleRate = 48000,
    this.durationSeconds = 4,
    this.amplitude = 0.02,
    this.toneHz = 10000,
    this.startHz = 3000,
    this.endHz = 10000,
    this.sweepSeconds = 0.02,
    this.rangeMeters = 0.6,
    this.motionMeters = 0.12,
    this.motionHz = 0.7,
    this.seed = 42,
    this.startupSamples = 128,
    this.noiseAmplitude = 0.00001,
  });
  final ProbeMode mode;
  final Scenario scenario;
  final int sampleRate, seed, startupSamples;
  final double durationSeconds, amplitude, toneHz, startHz, endHz;
  final double sweepSeconds,
      rangeMeters,
      motionMeters,
      motionHz,
      noiseAmplitude;
  static const soundSpeed = 343.0;
  static const minRange = 0.15;
  static const maxRange = 1.2;
  int get samples => (sampleRate * durationSeconds).round();
  int get sweepSamples => (sampleRate * sweepSeconds).round();
  double get actualSweepSeconds => sweepSamples / sampleRate;
  double get slope => (endHz - startHz) / actualSweepSeconds;
  bool get transmitterOn =>
      scenario != Scenario.transmitterOff && scenario != Scenario.silence;
  void validate() {
    if (sampleRate < 22050 ||
        sampleRate > 96000 ||
        !durationSeconds.isFinite ||
        durationSeconds < 1 ||
        durationSeconds > 10 ||
        !amplitude.isFinite ||
        amplitude <= 0 ||
        amplitude > 0.05 ||
        !toneHz.isFinite ||
        toneHz <= 0 ||
        toneHz >= sampleRate / 2 ||
        !startHz.isFinite ||
        !endHz.isFinite ||
        startHz <= 0 ||
        endHz <= startHz ||
        endHz >= sampleRate / 2 ||
        !sweepSeconds.isFinite ||
        sweepSeconds < 0.015 ||
        sweepSeconds > 0.05 ||
        !rangeMeters.isFinite ||
        rangeMeters < 0.3 ||
        rangeMeters > 1 ||
        !motionMeters.isFinite ||
        motionMeters < 0 ||
        motionMeters > 0.14 ||
        !motionHz.isFinite ||
        motionHz <= 0 ||
        motionHz > 2 ||
        startupSamples < 0 ||
        startupSamples > sampleRate ~/ 5 ||
        !noiseAmplitude.isFinite ||
        noiseAmplitude < 0 ||
        noiseAmplitude > 0.01) {
      throw ArgumentError(
        'Invalid configuration: duration 1–10 s, amplitude (0, 0.05], frequencies below Nyquist, range 0.3–1 m.',
      );
    }
    // A real mixer also produces a sum component, possibly folded by sampling.
    // Keep that component away from the selected difference-frequency band.
    if (mode == ProbeMode.chirp) {
      final beatLimit = 2 * maxRange / soundSpeed * slope;
      final validSamples =
          sweepSamples - (2 * maxRange / soundSpeed * sampleRate).ceil();
      final margin = 3 * sampleRate / validSamples;
      final lowestSumOrAlias = (2 * startHz < sampleRate - 2 * endHz)
          ? 2 * startHz
          : sampleRate - 2 * endHz;
      if (validSamples < 32 || lowestSumOrAlias <= beatLimit + margin) {
        throw ArgumentError(
          'Chirp band aliases mixer sum into the supported beat band. Choose a supported preset.',
        );
      }
    }
  }

  Map<String, Object> toJson() => {
    'mode': mode.name,
    'scenario': scenario.name,
    'sampleRate': sampleRate,
    'durationSeconds': durationSeconds,
    'amplitude': amplitude,
    'toneHz': toneHz,
    'startHz': startHz,
    'endHz': endHz,
    'sweepSamples': sweepSamples,
    'actualSweepSeconds': actualSweepSeconds,
    'rangeMeters': rangeMeters,
    'motionMeters': motionMeters,
    'motionHz': motionHz,
    'seed': seed,
    'startupSamples': startupSamples,
    'noiseAmplitude': noiseAmplitude,
    'soundSpeedMetersPerSecond': soundSpeed,
  };
}

class AudioCapture {
  AudioCapture({
    required this.config,
    required this.emitted,
    required this.received,
    required this.startedUtc,
    this.sourceKind = 'SIMULATED',
    this.backendId = 'simulated-v1',
    this.cancelled = false,
    this.status = const [],
    this.elapsedMicroseconds = 0,
  });
  final ExperimentConfig config;
  final Float64List emitted, received;
  final DateTime startedUtc;
  final String sourceKind, backendId;
  final bool cancelled;
  final List<String> status;
  final int elapsedMicroseconds;
}

class AnalysisFrame {
  const AnalysisFrame(this.time, this.power, this.movement, this.range);
  final double time, movement;
  final List<double> power;
  final double? range;
}

class AnalysisResult {
  const AnalysisResult({
    required this.axis,
    required this.frames,
    required this.quality,
    required this.settings,
    required this.axisLabel,
    required this.threshold,
    this.alignmentSamples,
    this.nativeBinWidth = 0,
  });
  final List<double> axis;
  final List<AnalysisFrame> frames;
  final List<String> quality;
  final Map<String, Object?> settings;
  final String axisLabel;
  final double threshold, nativeBinWidth;
  final int? alignmentSamples;
  bool get valid => quality.isEmpty && frames.isNotEmpty;
  bool get movementDetected =>
      valid && frames.where((f) => f.movement > threshold).length >= 2;
  Map<String, Object?> toJson() => {
    'algorithm': 'pcm-dsp-v1',
    'axis': axis,
    'axisLabel': axisLabel,
    'threshold': threshold,
    'alignmentSamples': alignmentSamples,
    'nativeBinWidth': nativeBinWidth,
    'quality': quality,
    'settings': settings,
    'movementDetected': movementDetected,
    'frames': [
      for (final f in frames)
        {
          'seconds': f.time,
          'power': f.power,
          'movement': f.movement,
          'equivalentRangeMeters': f.range,
        },
    ],
  };
}
