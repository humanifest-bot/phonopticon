import 'dart:math' as math;
import '../domain/experiment.dart';
import 'spectrum.dart';

AnalysisResult analyze(AudioCapture audio) {
  final c = audio.config;
  final quality = <String>[...audio.status];
  if (audio.cancelled) quality.add('Cancelled trial');
  if (audio.received.length != c.samples || audio.emitted.length != c.samples)
    quality.add('Incomplete PCM');
  if (audio.received.any((x) => !x.isFinite) ||
      audio.emitted.any((x) => !x.isFinite))
    quality.add('Nonfinite PCM');
  if (audio.received.any((x) => x.abs() >= 1)) quality.add('Clipped PCM');
  if (quality.isNotEmpty)
    return AnalysisResult(
      axis: [],
      frames: [],
      quality: quality,
      settings: {},
      axisLabel: '',
      threshold: 0.15,
    );
  return c.mode == ProbeMode.tone ? _tone(audio) : _chirp(audio);
}

AnalysisResult _tone(AudioCapture audio) {
  final c = audio.config;
  final n = nextPowerOfTwo((c.sampleRate * 0.65).round());
  final hop = n ~/ 4;
  final bins = [
    for (var k = 0; k <= n ~/ 2; k++)
      if ((k * c.sampleRate / n - c.toneHz).abs() <= 100) k,
  ];
  final axis = [for (final k in bins) k * c.sampleRate / n - c.toneHz];
  final frames = <AnalysisFrame>[];
  for (
    var offset = (c.sampleRate * 0.05).round();
    offset + n <= audio.received.length;
    offset += hop
  ) {
    final p = spectrum(audio.received.sublist(offset, offset + n));
    var sidebands = 0.0;
    for (var j = 0; j < bins.length; j++) {
      if (axis[j].abs() >= 6 && axis[j].abs() <= 80) sidebands += p[bins[j]];
    }
    final m = sidebands / (c.amplitude * c.amplitude * 0.04);
    frames.add(
      AnalysisFrame(
        (offset + n / 2) / c.sampleRate,
        [for (final k in bins) p[k]],
        m,
        null,
      ),
    );
  }
  return AnalysisResult(
    axis: axis,
    frames: frames,
    quality: [],
    axisLabel: 'Doppler offset (Hz)',
    threshold: 0.15,
    nativeBinWidth: c.sampleRate / n,
    settings: {
      'window': 'Hann',
      'windowSamples': n,
      'hopSamples': hop,
      'carrierExclusionHz': 6,
      'sidebandMaxHz': 80,
      'normalization': 'amplitude² × 0.04; fixed fixture reference',
      'thresholdVersion': 'fixture-v1-not-physical-calibration',
    },
  );
}

// Alignment uses PCM correlation only, not fixture truth/config.startupSamples.
int? alignDirectPath(AudioCapture audio, {int? anchor}) {
  final c = audio.config;
  final tx = audio.emitted, rx = audio.received;
  final count = math.min(c.sweepSamples, tx.length ~/ 3);
  final base = anchor ?? c.sweepSamples * 2;
  if (base + count >= tx.length || rx.length < tx.length) return null;
  var best = 0.0, bestLag = -1;
  var txPower = 0.0;
  for (var j = 0; j < count; j++) {
    txPower += tx[base + j] * tx[base + j];
  }
  if (txPower < 1e-12) return null;
  // Search less than one chirp to avoid periodic ambiguity; cap is a declared contract.
  for (var lag = 0; lag < c.sweepSamples; lag++) {
    if (base + count + lag > rx.length) break;
    var dot = 0.0, rxPower = 0.0;
    for (var j = 0; j < count; j++) {
      dot += tx[base + j] * rx[base + lag + j];
      rxPower += rx[base + lag + j] * rx[base + lag + j];
    }
    final score = dot / math.sqrt(math.max(1e-30, txPower * rxPower));
    if (score > best) {
      best = score;
      bestLag = lag;
    }
  }
  return best >= 0.5 ? bestLag : null;
}

AnalysisResult _chirp(AudioCapture audio) {
  final c = audio.config;
  final lag = alignDirectPath(audio);
  if (lag == null)
    return AnalysisResult(
      axis: [],
      frames: [],
      quality: ['No reliable direct-path alignment'],
      settings: {
        'search': 'positive correlation, 0 <= lag < sweepSamples, minimum 0.5',
      },
      axisLabel: 'Equivalent range (m)',
      threshold: 0.15,
    );
  final endAnchor =
      ((audio.emitted.length ~/ c.sweepSamples) - 3) * c.sweepSamples;
  final endLag = alignDirectPath(audio, anchor: endAnchor);
  if (endLag == null || (endLag - lag).abs() > 1) {
    return AnalysisResult(
      axis: [],
      frames: [],
      quality: ['Alignment drift or weak end-of-trial reference'],
      settings: {'startLagSamples': lag, 'endLagSamples': endLag},
      axisLabel: 'Equivalent range (m)',
      threshold: 0.15,
    );
  }
  final guard =
      (2 *
              ExperimentConfig.maxRange /
              ExperimentConfig.soundSpeed *
              c.sampleRate)
          .ceil();
  final valid = c.sweepSamples - guard;
  final n = nextPowerOfTwo(valid);
  final spacing =
      c.sampleRate / n * ExperimentConfig.soundSpeed / (2 * c.slope);
  final nativeWidth =
      c.sampleRate / valid * ExperimentConfig.soundSpeed / (2 * c.slope);
  final bins = [
    for (var k = 0; k <= n ~/ 2; k++)
      if (k * spacing >= ExperimentConfig.minRange &&
          k * spacing <= ExperimentConfig.maxRange)
        k,
  ];
  final axis = [for (final k in bins) k * spacing];
  final frames = <AnalysisFrame>[];
  List<double>? previous;
  final ref = math.pow(c.amplitude, 4) * 0.04;
  for (
    var start = c.sweepSamples * 2;
    start + c.sweepSamples + lag <= audio.received.length;
    start += c.sweepSamples
  ) {
    final mixed = <double>[];
    // Mix against the known real chirp. The bounded beat-band FFT
    // selects the difference term; high sum-frequency products are excluded.
    for (var j = guard; j < c.sweepSamples; j++) {
      mixed.add(audio.received[start + lag + j] * audio.emitted[start + j]);
    }
    final full = spectrum(mixed, fftSize: n);
    final p = [for (final k in bins) full[k]];
    var peak = 0;
    for (var k = 1; k < p.length; k++) {
      if (p[k] > p[peak]) peak = k;
    }
    final sorted = [...p]..sort();
    final floor = math.max(1e-30, sorted[sorted.length ~/ 2]);
    final reliable =
        p[peak] > math.pow(c.amplitude, 4) * 0.0001 && p[peak] / floor > 8;
    var change = 0.0;
    if (previous != null) {
      for (var k = 0; k < p.length; k++) {
        change += (p[k] - previous[k]).abs();
      }
    }
    frames.add(
      AnalysisFrame(
        (start + c.sweepSamples / 2) / c.sampleRate,
        p,
        change / math.max(1e-30, ref),
        reliable ? axis[peak] : null,
      ),
    );
    previous = p;
  }
  return AnalysisResult(
    axis: axis,
    frames: frames,
    quality: [],
    axisLabel: 'Equivalent range (m)',
    threshold: 0.15,
    alignmentSamples: lag,
    nativeBinWidth: nativeWidth,
    settings: {
      'window': 'Hann',
      'validSamples': valid,
      'fftSize': n,
      'guardSamples': guard,
      'sweepSamples': c.sweepSamples,
      'hopSamples': c.sweepSamples,
      'differenceBandMaxHz':
          ExperimentConfig.maxRange * 2 * c.slope / ExperimentConfig.soundSpeed,
      'endLagSamples': endLag,
      'alignment':
          'strongest positive direct-path PCM correlation; lag < one sweep',
      'normalization': 'amplitude⁴ × 0.04; fixed fixture reference',
      'thresholdVersion': 'fixture-v1-not-physical-calibration',
      'rangeCaveat':
          'Equivalent excess range relative to aligned direct path; colocated approximation',
    },
  );
}
