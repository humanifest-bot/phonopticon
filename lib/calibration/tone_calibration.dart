import 'dart:convert';
import 'dart:math' as math;
import '../domain/experiment.dart';
import '../export/artifacts.dart';

// A deterministic, experimental calibration rule, not a learned classifier.
// The frame bands/trim/quantile are fixed before held-out trials are collected.
const toneCalibrationVersion = 'received-tone-ratio-v1';

double quantile(List<double> values, double q) {
  if (values.isEmpty || values.any((x) => !x.isFinite)) {
    throw ArgumentError('Insufficient finite calibration observations');
  }
  final sorted = [...values]..sort();
  final p = (sorted.length - 1) * q;
  return sorted[p.floor()] * (1 - (p - p.floor())) +
      sorted[p.ceil()] * (p - p.floor());
}

String captureFingerprint(AudioCapture c) =>
    fingerprint(wavBytes(c.received, c.actualSampleRate));

String routeSignature(AudioCapture c) {
  final metadata = c.deviceMetadata;
  final settings = metadata['inputSettings'] as Map? ?? {};
  return jsonEncode([
    c.backendId,
    c.actualSampleRate,
    c.actualChannels,
    metadata['inputLabel'],
    for (final key in [
      'sampleRate',
      'channelCount',
      'echoCancellation',
      'noiseSuppression',
      'autoGainControl',
      'voiceIsolation',
    ])
      settings[key],
  ]);
}

class ToneFeatures {
  ToneFeatures(this.carrier, this.ratios, this.times);
  final List<double> carrier, ratios, times;
}

ToneFeatures toneFeatures(AudioCapture c, AnalysisResult r) {
  if (c.sourceKind != 'PHYSICAL' ||
      c.config.mode != ProbeMode.tone ||
      c.cancelled ||
      !r.valid ||
      c.config.durationSeconds < 3) {
    throw ArgumentError(
      'A complete physical tone capture of at least 3 s is required',
    );
  }
  final carrier = <double>[], ratios = <double>[], times = <double>[];
  for (final frame in r.frames) {
    // Exclude mouse/start/stop transients; keep the same trim for every role.
    if (frame.time < .8 || frame.time > c.config.durationSeconds - .8) continue;
    var direct = 0.0, side = 0.0;
    for (var i = 0; i < r.axis.length; i++) {
      final offset = r.axis[i].abs();
      if (offset < 3) direct += frame.power[i];
      if (offset >= 6 && offset <= 80) side += frame.power[i];
    }
    carrier.add(direct);
    ratios.add(side / math.max(1e-24, direct));
    times.add(frame.time);
  }
  if (carrier.length < 8) throw ArgumentError('Too few interior FFT frames');
  return ToneFeatures(carrier, ratios, times);
}

class CalibrationObservation {
  const CalibrationObservation(this.capture, this.result);
  final AudioCapture capture;
  final AnalysisResult result;
}

class ToneCalibration {
  const ToneCalibration({
    required this.id,
    required this.sampleRate,
    required this.toneHz,
    required this.amplitude,
    required this.durationSeconds,
    required this.route,
    required this.carrierFloor,
    required this.threshold,
    required this.trainingFingerprints,
    required this.trainingCounts,
  });
  final String id, route;
  final int sampleRate;
  final double toneHz, amplitude, durationSeconds, carrierFloor, threshold;
  final List<String> trainingFingerprints;
  final Map<String, int> trainingCounts;

  static ToneCalibration fit(List<CalibrationObservation> observations) {
    final stationary = <ToneFeatures>[],
        moving = <ToneFeatures>[],
        off = <ToneFeatures>[];
    if (observations.isEmpty) throw ArgumentError('No calibration data');
    final first = observations.first.capture;
    final hashes = <String>[];
    for (final o in observations) {
      final c = o.capture;
      if (routeSignature(c) != routeSignature(first) ||
          c.config.sampleRate != first.config.sampleRate ||
          c.config.toneHz != first.config.toneHz ||
          c.config.amplitude != first.config.amplitude ||
          c.config.durationSeconds != first.config.durationSeconds) {
        throw ArgumentError('Calibration route or waveform settings differ');
      }
      final hash = captureFingerprint(c);
      if (hashes.contains(hash))
        throw ArgumentError('Duplicate calibration PCM');
      hashes.add(hash);
      final features = toneFeatures(c, o.result);
      switch (c.config.scenario) {
        case Scenario.stationary:
          stationary.add(features);
        case Scenario.moving:
          moving.add(features);
        case Scenario.transmitterOff:
          off.add(features);
        default:
          throw ArgumentError('Unsupported calibration condition');
      }
    }
    if (stationary.isEmpty || moving.isEmpty || off.isEmpty) {
      throw ArgumentError(
        'Stationary/on, moving/on and moving/off calibration required',
      );
    }
    final onCarrier = quantile([for (final f in stationary) ...f.carrier], .1);
    final offCarrier = quantile([for (final f in off) ...f.carrier], .95);
    if (onCarrier < math.max(1e-18, offCarrier * 100)) {
      throw StateError(
        'Calibration failed: received tone is not 20 dB above off noise',
      );
    }
    final floor = math.sqrt(onCarrier * math.max(1e-24, offCarrier));
    double score(ToneFeatures f) {
      if (f.carrier.where((x) => x >= floor).length / f.carrier.length < .8) {
        throw StateError(
          'Calibration failed: unstable or missing received tone',
        );
      }
      return quantile(f.ratios, .8);
    }

    final negative = stationary.map(score).reduce(math.max);
    final positive = moving.map(score).reduce(math.min);
    if (positive <= math.max(1e-8, negative * 1.5)) {
      throw StateError(
        'Calibration failed: stationary and moving calibration overlap',
      );
    }
    final threshold = math.sqrt(math.max(1e-12, negative) * positive);
    final core = jsonEncode([
      toneCalibrationVersion,
      hashes,
      floor,
      threshold,
      first.config.toJson(),
      routeSignature(first),
    ]);
    return ToneCalibration(
      id: fingerprint(utf8.encode(core)),
      sampleRate: first.actualSampleRate,
      toneHz: first.config.toneHz,
      amplitude: first.config.amplitude,
      durationSeconds: first.config.durationSeconds,
      route: routeSignature(first),
      carrierFloor: floor,
      threshold: threshold,
      trainingFingerprints: List.unmodifiable(hashes),
      trainingCounts: {
        'stationary': stationary.length,
        'moving': moving.length,
        'off': off.length,
      },
    );
  }

  Map<String, Object?> toJson() => {
    'version': toneCalibrationVersion,
    'id': id,
    'sampleRate': sampleRate,
    'toneHz': toneHz,
    'amplitude': amplitude,
    'durationSeconds': durationSeconds,
    'routeSignature': route,
    'carrierFloor': carrierFloor,
    'threshold': threshold,
    'trainingFingerprints': trainingFingerprints,
    'trainingCounts': trainingCounts,
    'trimSeconds': .8,
    'trialQuantile': .8,
    'minimumCarrierFraction': .8,
    'carrierBandHz': [0, 3],
    'sidebandHz': [6, 80],
    'fingerprintAlgorithm': 'FNV-1a-32; noncryptographic',
    'physicalValidation': false,
  };

  factory ToneCalibration.fromJson(Map<String, dynamic> m) {
    if (m['version'] != toneCalibrationVersion ||
        m['trimSeconds'] != .8 ||
        m['trialQuantile'] != .8 ||
        m['minimumCarrierFraction'] != .8 ||
        jsonEncode(m['carrierBandHz']) != '[0,3]' ||
        jsonEncode(m['sidebandHz']) != '[6,80]' ||
        m['physicalValidation'] != false) {
      throw FormatException('Unsupported calibration rule');
    }
    double number(String key) {
      final n = (m[key] as num).toDouble();
      if (!n.isFinite || n <= 0) throw FormatException('Invalid $key');
      return n;
    }

    final rate = m['sampleRate'] as int;
    final hz = number('toneHz'),
        amp = number('amplitude'),
        duration = number('durationSeconds');
    final floor = number('carrierFloor'), threshold = number('threshold');
    if (rate < 22050 ||
        rate > 96000 ||
        hz >= rate / 2 ||
        amp > .05 ||
        duration < 3 ||
        duration > 10 ||
        m['routeSignature'] is! String ||
        m['id'] is! String)
      throw FormatException('Invalid calibration settings');
    final hashes = (m['trainingFingerprints'] as List).cast<String>();
    final counts = (m['trainingCounts'] as Map).map(
      (k, v) => MapEntry(k as String, v as int),
    );
    if (hashes.length < 3 ||
        hashes.toSet().length != hashes.length ||
        ['stationary', 'moving', 'off'].any((k) => (counts[k] ?? 0) < 1) ||
        counts.values.reduce((a, b) => a + b) != hashes.length) {
      throw FormatException('Invalid calibration provenance');
    }
    return ToneCalibration(
      id: m['id'],
      sampleRate: rate,
      toneHz: hz,
      amplitude: amp,
      durationSeconds: duration,
      route: m['routeSignature'],
      carrierFloor: floor,
      threshold: threshold,
      trainingFingerprints: List.unmodifiable(hashes),
      trainingCounts: Map.unmodifiable(counts),
    );
  }

  AnalysisResult apply(AudioCapture c, AnalysisResult raw) {
    var quality = <String>[...raw.quality];
    ToneFeatures? f;
    try {
      if (c.actualSampleRate != sampleRate ||
          c.config.toneHz != toneHz ||
          c.config.amplitude != amplitude ||
          c.config.durationSeconds != durationSeconds ||
          routeSignature(c) != route)
        throw StateError('Calibration route/settings mismatch');
      if (trainingFingerprints.contains(captureFingerprint(c))) {
        throw StateError(
          'Calibration recording cannot count as held-out evaluation',
        );
      }
      f = toneFeatures(c, raw);
    } catch (e) {
      quality.add(e.toString());
    }
    final carrierFraction = f == null
        ? 0.0
        : f.carrier.where((x) => x >= carrierFloor).length / f.carrier.length;
    final score = f == null ? null : quantile(f.ratios, .8);
    if (f != null && carrierFraction < .8) {
      quality.add('Probe absent or too weak; movement decision unavailable');
    }
    final decision = quality.isEmpty && score != null
        ? score > threshold
        : null;
    final frames = <AnalysisFrame>[];
    if (f != null) {
      for (var i = 0; i < f.times.length; i++) {
        final original = raw.frames.firstWhere((x) => x.time == f!.times[i]);
        frames.add(
          AnalysisFrame(original.time, original.power, f.ratios[i], null),
        );
      }
    }
    return AnalysisResult(
      axis: raw.axis,
      frames: frames,
      quality: quality,
      settings: {
        ...raw.settings,
        'normalization': 'received sideband power / received carrier power',
        'thresholdVersion': toneCalibrationVersion,
        'calibrationProfile': toJson(),
        'trialScore': score,
        'carrierFraction': carrierFraction,
        'decisionAvailable': decision != null,
        'trialQuantile': .8,
        'rule':
            '80th percentile of interior frame ratios; carrier required in 80% of frames',
      },
      axisLabel: raw.axisLabel,
      threshold: threshold,
      nativeBinWidth: raw.nativeBinWidth,
      movementDecision: decision,
    );
  }
}
