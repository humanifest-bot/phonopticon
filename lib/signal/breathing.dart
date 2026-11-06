import 'dart:math' as math;
import 'dart:typed_data';
import '../domain/experiment.dart';

const breathingVersion = 'coherent-chirp-gate-v1';
const probeMatchFloor = .25;

// Quadrature projection on a delayed replica of the periodic FMCW sweep.
// A first difference suppresses low-frequency background in both operands.
class _ChirpTemplate {
  _ChirpTemplate(ExperimentConfig c, double delay)
    : sine = Float64List(c.sweepSamples),
      cosine = Float64List(c.sweepSamples),
      window = Float64List(c.sweepSamples) {
    double phase(double sample) {
      final t = ((sample - delay) % c.sweepSamples) / c.sampleRate;
      return 2 * math.pi * (c.startHz * t + .5 * c.slope * t * t);
    }

    for (var j = 0; j < sine.length; j++) {
      final current = phase(j.toDouble()), previous = phase(j - 1.0);
      final w = .5 - .5 * math.cos(2 * math.pi * j / (sine.length - 1));
      final s = math.sin(current) - math.sin(previous);
      final q = math.cos(current) - math.cos(previous);
      sine[j] = s * w;
      cosine[j] = q * w;
      window[j] = w;
      sinePower += s * s * w;
      cosinePower += q * q * w;
    }
  }
  final Float64List sine, cosine, window;
  double sinePower = 0, cosinePower = 0;

  ({double i, double q, double match}) project(Float64List input, int offset) {
    var i = 0.0, q = 0.0, power = 0.0;
    for (var j = 0; j < sine.length; j++) {
      final x = input[offset + j];
      i += x * sine[j];
      q += x * cosine[j];
      power += x * x * window[j];
    }
    final explained = i * i / sinePower + q * q / cosinePower;
    return (
      i: i / sinePower,
      q: q / cosinePower,
      match: math.sqrt(explained / math.max(1e-30, power)).clamp(0.0, 1.0),
    );
  }
}

Float64List _fold(Float64List rx, int start, int n, int sweeps, {int? length}) {
  final folded = Float64List(length ?? n);
  for (var s = 0; s < sweeps; s++) {
    final base = start + s * n;
    for (var j = 0; j < folded.length; j++) {
      folded[j] += (rx[base + j] - rx[base + j - 1]) / sweeps;
    }
  }
  return folded;
}

({int lag, double match}) _align(
  Float64List rx,
  int start,
  int n,
  _ChirpTemplate ref,
) {
  final folded = _fold(rx, start, n, 8, length: 2 * n - 1);
  var bestLag = 0, bestMatch = 0.0;
  for (var lag = 0; lag < n; lag++) {
    final match = ref.project(folded, lag).match;
    if (match > bestMatch) {
      bestMatch = match;
      bestLag = lag;
    }
  }
  return (lag: bestLag, match: bestMatch);
}

List<double> _detrend(List<double> x, List<double> times) {
  final mean = x.reduce((a, b) => a + b) / x.length;
  final center = times.reduce((a, b) => a + b) / times.length;
  var cov = 0.0, varTime = 0.0;
  for (var j = 0; j < x.length; j++) {
    final t = times[j] - center;
    cov += (x[j] - mean) * t;
    varTime += t * t;
  }
  return [
    for (var j = 0; j < x.length; j++)
      x[j] - mean - cov / varTime * (times[j] - center),
  ];
}

// Regress I and Q on a common sinusoid across a fixed slow-time search band.
// Sum explained energy across the same range grid at every frequency.
({double hz, double fraction, double rms, int displayBin}) _rhythm(
  List<List<double>> channels,
  List<double> times,
) {
  var bestEnergy = 0.0, bestHz = .1, displayBin = 0;
  final energy = channels.fold<double>(
    0,
    (sum, x) => sum + x.fold<double>(0, (a, b) => a + b * b),
  );
  for (var step = 10; step <= 60; step++) {
    final hz = step / 100;
    final sine = [for (final t in times) math.sin(2 * math.pi * hz * t)];
    final cosine = [for (final t in times) math.cos(2 * math.pi * hz * t)];
    var ss = 0.0, cc = 0.0, sc = 0.0;
    for (var j = 0; j < times.length; j++) {
      ss += sine[j] * sine[j];
      cc += cosine[j] * cosine[j];
      sc += sine[j] * cosine[j];
    }
    final determinant = ss * cc - sc * sc;
    var explained = 0.0, largest = 0.0, channel = 0;
    for (var k = 0; k < channels.length; k++) {
      var xs = 0.0, xc = 0.0;
      for (var j = 0; j < times.length; j++) {
        xs += channels[k][j] * sine[j];
        xc += channels[k][j] * cosine[j];
      }
      final e = (cc * xs * xs - 2 * sc * xs * xc + ss * xc * xc) / determinant;
      explained += e;
      if (e > largest) {
        largest = e;
        channel = k;
      }
    }
    if (explained > bestEnergy) {
      bestEnergy = explained;
      bestHz = hz;
      displayBin = channel;
    }
  }
  return (
    hz: bestHz,
    fraction: bestEnergy / math.max(energy, 1e-30),
    rms: math.sqrt(bestEnergy / (times.length * channels.length / 2)),
    displayBin: displayBin,
  );
}

AnalysisResult analyzeBreathing(AudioCapture audio) {
  final c = audio.config, rx = audio.received, n = audio.config.sweepSamples;
  final axis = [for (var j = -3; j <= 3; j++) c.breathingGateMeters + j * .03];
  final settings = <String, Object?>{
    'breathingAlgorithm': breathingVersion,
    'gateCenterMeters': c.breathingGateMeters,
    'probeMatchFloor': probeMatchFloor,
    'searchHz': [.1, .6],
    'trialType': 'periodic reflector motion feasibility',
  };
  AnalysisResult unavailable(String reason) => AnalysisResult(
    axis: axis,
    frames: [],
    quality: [reason],
    settings: settings,
    axisLabel: 'Equivalent echo range (m)',
    threshold: 0,
    movementDecision: false,
  );
  final reference = _ChirpTemplate(c, 0);
  final warmup = (1 / c.actualSweepSeconds).ceil() * n;
  final tail = (rx.length - warmup) ~/ n * n;
  final first = _align(rx, warmup, n, reference);
  final last = _align(rx, tail - 9 * n, n, reference);
  settings.addAll({
    'probeMatchStart': first.match,
    'probeMatchEnd': last.match,
    'startLagSamples': first.lag,
    'endLagSamples': last.lag,
  });
  if (first.match < probeMatchFloor || last.match < probeMatchFloor) {
    return unavailable('No coherent chirp probe found');
  }
  final shift = (first.lag - last.lag).abs();
  if (math.min(shift, n - shift) > 2)
    return unavailable('Chirp timing changed during capture');
  final group = math.max(1, (.1 / c.actualSweepSeconds).round());
  final templates = [
    for (final range in axis)
      _ChirpTemplate(c, 2 * range * c.sampleRate / ExperimentConfig.soundSpeed),
  ];
  final times = <double>[], powers = <List<double>>[], direct = <double>[];
  final channels = [for (var i = 0; i < 2 * axis.length; i++) <double>[]];
  var total = 0;
  for (
    var start = warmup;
    start + group * n + first.lag <= tail;
    start += group * n
  ) {
    total++;
    final folded = _fold(rx, start + first.lag, n, group);
    final r = reference.project(folded, 0);
    final amplitude = math.sqrt(r.i * r.i + r.q * r.q);
    if (r.match < .18 || amplitude < 1e-8) continue;
    times.add((start + group * n / 2) / c.sampleRate);
    direct.add(amplitude);
    final power = <double>[];
    for (var k = 0; k < templates.length; k++) {
      final v = templates[k].project(folded, 0);
      channels[2 * k].add((v.i * r.i + v.q * r.q) / amplitude);
      channels[2 * k + 1].add((v.q * r.i - v.i * r.q) / amplitude);
      power.add(v.i * v.i + v.q * v.q);
    }
    powers.add(power);
  }
  settings['usableFrames'] = times.length;
  settings['totalFrames'] = total;
  if (times.length < 10 || times.length < .9 * total)
    return unavailable('Too many weak chirp frames');
  final sorted = [...direct]..sort();
  final scale = sorted[sorted.length ~/ 2];
  final traces = [
    for (final x in channels) _detrend([for (final v in x) v / scale], times),
  ];
  final rhythm = _rhythm(traces, times);
  final trace = traces[rhythm.displayBin];
  final bin = rhythm.displayBin ~/ 2;
  settings.addAll({
    'peakHz': rhythm.hz,
    'periodicFraction': rhythm.fraction,
    'periodicRms': rhythm.rms,
    'observedSpanSeconds': times.last - times.first,
    'sweepsPerFrame': group,
    'traceGateMeters': axis[bin],
    'traceComponent': rhythm.displayBin.isEven ? 'I' : 'Q',
    'referenceAmplitude': scale,
  });
  return AnalysisResult(
    axis: axis,
    frames: [
      for (var i = 0; i < times.length; i++)
        AnalysisFrame(times[i], powers[i], trace[i], null),
    ],
    quality: [],
    settings: settings,
    axisLabel: 'Equivalent echo range (m)',
    threshold: 0,
    alignmentSamples: first.lag,
    nativeBinWidth: ExperimentConfig.soundSpeed / (2 * (c.endHz - c.startHz)),
    movementDecision: false,
  );
}
