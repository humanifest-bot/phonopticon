import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import '../domain/experiment.dart';

Uint8List wavBytes(Float64List samples, int rate) {
  final out = ByteData(44 + samples.length * 4);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      out.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  out.setUint32(4, out.lengthInBytes - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 3, Endian.little);
  out.setUint16(22, 1, Endian.little);
  out.setUint32(24, rate, Endian.little);
  out.setUint32(28, rate * 4, Endian.little);
  out.setUint16(32, 4, Endian.little);
  out.setUint16(34, 32, Endian.little);
  text(36, 'data');
  out.setUint32(40, samples.length * 4, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    out.setFloat32(44 + i * 4, samples[i], Endian.little);
  }
  return out.buffer.asUint8List();
}

// Reproducibility fingerprint, not a cryptographic signature or approval receipt.
String fingerprint(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String movementSvg(AnalysisResult r, {String sourceKind = 'SIMULATED'}) {
  if (r.frames.isEmpty)
    return '<svg xmlns="http://www.w3.org/2000/svg" width="800" height="240"><text x="20" y="40">$sourceKind — no valid analysis</text></svg>';
  final maxTime = r.frames.last.time;
  final maxValue = math.max(
    r.threshold * 2,
    r.frames.map((f) => f.movement).reduce(math.max),
  );
  final points = r.frames
      .map(
        (f) =>
            '${(40 + f.time / maxTime * 720).toStringAsFixed(2)},${(200 - f.movement / maxValue * 150).toStringAsFixed(2)}',
      )
      .join(' ');
  final y = 200 - r.threshold / maxValue * 150;
  return '<svg xmlns="http://www.w3.org/2000/svg" width="800" height="250" viewBox="0 0 800 250"><rect width="800" height="250" fill="#f6f8fb"/><text x="40" y="25">$sourceKind movement score — fixture threshold ${r.threshold}</text><line x1="40" x2="760" y1="$y" y2="$y" stroke="#b05820" stroke-dasharray="6 4"/><polyline points="$points" fill="none" stroke="#006d77" stroke-width="2"/><text x="40" y="230">Time (seconds), 0–${maxTime.toStringAsFixed(2)}; normalized score 0–${maxValue.toStringAsFixed(3)}</text></svg>';
}

String spectrumSvg(AnalysisResult r, {String sourceKind = 'SIMULATED'}) {
  if (r.frames.isEmpty || r.axis.isEmpty)
    return '<svg xmlns="http://www.w3.org/2000/svg" width="800" height="240"><text x="20" y="40">$sourceKind — no reliable spectrum</text></svg>';
  final out = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" width="800" height="400" viewBox="0 0 800 400"><rect width="800" height="400" fill="#08162c"/><g fill="white" font-family="sans-serif" font-size="12"><text x="60" y="24">$sourceKind — ${r.axisLabel} versus time</text><text x="60" y="380">Time (seconds), 0–${r.frames.last.time.toStringAsFixed(2)}</text><text x="5" y="52">${r.axis.last.toStringAsFixed(2)}</text><text x="5" y="346">${r.axis.first.toStringAsFixed(2)}</text></g>',
  );
  final low = r.axisLabel.startsWith('Doppler') ? -120.0 : -180.0;
  final high = low + 100;
  for (var t = 0; t < r.frames.length; t++) {
    for (var k = 0; k < r.axis.length; k++) {
      final db =
          10 * math.log(math.max(1e-24, r.frames[t].power[k])) / math.ln10;
      final level = ((db - low) / (high - low)).clamp(0.0, 1.0);
      final red = (15 + 225 * level).round(),
          green = (25 + 170 * level).round(),
          blue = (45 + 45 * level).round();
      out.write(
        '<rect x="${60 + t * 720 / r.frames.length}" y="${45 + (r.axis.length - 1 - k) * 300 / r.axis.length}" width="${720 / r.frames.length + 0.1}" height="${300 / r.axis.length + 0.1}" fill="rgb($red,$green,$blue)"/>',
      );
    }
  }
  out.write(
    '<text x="60" y="363" fill="white" font-family="sans-serif" font-size="12">Absolute power scale: $low to $high dB re 1 sample²</text></svg>',
  );
  return out.toString();
}

Map<String, Object?> artifactBundle(
  AudioCapture c,
  AnalysisResult? result, {
  String? trialId,
}) {
  if (c.actualChannels != 1)
    throw UnsupportedError('Only mono PCM export is implemented.');
  final tx = wavBytes(c.emitted, c.config.sampleRate),
      rx = wavBytes(c.received, c.actualSampleRate);
  final r =
      result ??
      AnalysisResult(
        axis: [],
        frames: [],
        quality: [...c.status, 'Analysis unavailable'],
        settings: {},
        axisLabel: '',
        threshold: 0.15,
      );
  final csv = StringBuffer('seconds,movement,equivalent_range_m\n');
  for (final f in r.frames) {
    csv.writeln('${f.time},${f.movement},${f.range ?? ''}');
  }
  final exportConfig = Map<String, Object>.from(c.config.toJson());
  if (c.sourceKind != 'SIMULATED') {
    for (final key in [
      'seed',
      'rangeMeters',
      'motionMeters',
      'motionHz',
      'startupSamples',
      'noiseAmplitude',
    ]) {
      exportConfig.remove(key);
    }
  }
  final configBytes = utf8.encode(jsonEncode(exportConfig));
  return {
    'manifest': {
      'schemaVersion': 1,
      'trialId':
          trialId ?? 'trial-${DateTime.now().toUtc().microsecondsSinceEpoch}',
      'sourceKind': c.sourceKind,
      'backend': c.backendId,
      'startedUtc': c.startedUtc.toIso8601String(),
      'elapsedMicroseconds': c.elapsedMicroseconds,
      'cancelled': c.cancelled,
      'status': c.status,
      'sourceRevision': const String.fromEnvironment(
        'SOURCE_REVISION',
        defaultValue: 'unrecorded-development-build',
      ),
      'algorithmVersion': 'pcm-dsp-v1',
      'fixtureModel': c.sourceKind == 'SIMULATED'
          ? 'fractional-delay-echo-v1'
          : null,
      'fingerprintAlgorithm': 'FNV-1a-32 (noncryptographic)',
      'fingerprints': {
        'emitted.wav': fingerprint(tx),
        'received.wav': fingerprint(rx),
        'config': fingerprint(configBytes),
      },
      'config': exportConfig,
      'actualAudioFormat': {
        'sampleRate': c.actualSampleRate,
        'channels': c.actualChannels,
        'encoding': 'Float32 WAV',
      },
      'device': c.sourceKind == 'SIMULATED'
          ? 'none; generated PCM'
          : c.backendId,
      'deviceMetadata': c.deviceMetadata,
      'hardwareProcessing': c.sourceKind == 'SIMULATED'
          ? 'not applicable to simulation'
          : 'see deviceMetadata; not inferred',
      'calibration': c.sourceKind == 'SIMULATED'
          ? 'fixture-reference-v1; not physical calibration'
          : 'uncalibrated physical recording; fixture thresholds are exploratory only',
      'physicalValidation': false,
      'waveform': {
        'phase': 'sin; chirp phase reset each sweep',
        'rampSeconds': 0.01,
        if (c.sourceKind == 'SIMULATED') ...{
          'directGain': 0.6,
          'targetGain': 0.4,
          'staticEchoGain': 0.12,
          'staticEchoMeters': 1.07,
          'noise': 'seeded LCG uniform [-noiseAmplitude,+noiseAmplitude]',
        },
      },
      'interpretation':
          'Experimental workflow; physical recordings are not accepted validation. Equivalent range uses a colocated approximation.',
    },
    'files': {
      'emitted.wav.base64': base64Encode(tx),
      'received.wav.base64': base64Encode(rx),
      'metrics.csv': csv.toString(),
      'movement.svg': movementSvg(r, sourceKind: c.sourceKind),
      'spectrum.svg': spectrumSvg(r, sourceKind: c.sourceKind),
    },
    'analysis': r.toJson(),
  };
}
