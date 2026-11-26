import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/experiment.dart';
import '../signal/spectrum.dart';

/// Descriptive PCM measurements. These do not identify the cause of a spike.
class RecordingDiagnostics {
  const RecordingDiagnostics({
    required this.sampleRate,
    required this.durationSeconds,
    required this.sampleCount,
    required this.nonFiniteSamples,
    required this.zeroSamples,
    required this.clippedSamples,
    required this.rms,
    required this.probeLowHz,
    required this.probeHighHz,
    required this.probeBandFraction,
    required this.probeBandRms,
    required this.spectralWindows,
    required this.transientThreshold,
    required this.transientsSeconds,
    required this.probeMatchStart,
    required this.probeMatchEnd,
    required this.startLagSamples,
    required this.endLagSamples,
    required this.reliableAlignment,
    required this.transmitterOn,
  });

  final int sampleRate,
      sampleCount,
      nonFiniteSamples,
      zeroSamples,
      clippedSamples;
  final double durationSeconds, probeLowHz, probeHighHz;
  final double? rms;

  /// Fraction of sampled, windowed spectral energy in the nominal probe band.
  /// This is not an ambient-only measurement when the transmitter is on.
  final double? probeBandFraction;

  /// RMS estimated from sampled Hann-window spectra, in full-scale units.
  final double? probeBandRms;
  final int spectralWindows;
  final double transientThreshold;
  final List<double> transientsSeconds;
  final double? probeMatchStart, probeMatchEnd;
  final int? startLagSamples, endLagSamples;
  final bool? reliableAlignment;
  final bool transmitterOn;

  bool get exactlySilent => sampleCount > 0 && zeroSamples == sampleCount;
}

/// Measure 100 ms RMS windows; spectrum is sampled once per window using a
/// 1,024-sample Hann FFT. Transients are window centers exceeding both 3x the
/// median window RMS and 0.005 full scale; these are indicators, not causes.
RecordingDiagnostics summarizeRecording(
  AudioCapture capture, {
  AnalysisResult? analysis,
}) {
  final input = capture.received;
  final rate = capture.actualSampleRate;
  if (rate <= 0) throw ArgumentError('Sample rate must be positive');
  final c = capture.config;
  final low = c.mode == ProbeMode.tone ? c.toneHz - 100 : c.startHz;
  final high = c.mode == ProbeMode.tone ? c.toneHz + 100 : c.endHz;
  final windowSize = math.max(1024, (rate * .1).round());
  var sumSquares = 0.0, zeros = 0, clipped = 0, nonFinite = 0;
  var bandEnergy = 0.0, totalEnergy = 0.0, spectralWindows = 0;
  final windows = <({double time, double rms})>[];
  for (var start = 0; start < input.length; start += windowSize) {
    final end = math.min(start + windowSize, input.length);
    var localSquares = 0.0, valid = 0;
    for (var i = start; i < end; i++) {
      final x = input[i];
      if (!x.isFinite) {
        nonFinite++;
        continue;
      }
      if (x == 0) zeros++;
      if (x.abs() >= 1) clipped++;
      localSquares += x * x;
      valid++;
    }
    sumSquares += localSquares;
    if (valid > 0) {
      windows.add((
        time: (start + (end - start) / 2) / rate,
        rms: math.sqrt(localSquares / valid),
      ));
    }
    if (end - start >= 1024) {
      // Skip spectral estimation for a chunk containing invalid samples.
      final segment = input.sublist(start, start + 1024);
      if (segment.every((x) => x.isFinite)) {
        spectralWindows++;
        final bins = spectrum(segment);
        for (var k = 0; k < bins.length; k++) {
          final weighted = bins[k] * (k == 0 || k == 512 ? 1 : 2);
          totalEnergy += weighted;
          final frequency = k * rate / 1024;
          if (frequency >= low && frequency <= high) bandEnergy += weighted;
        }
      }
    }
  }
  final sorted = windows.map((w) => w.rms).toList()..sort();
  final median = sorted.isEmpty ? 0.0 : sorted[sorted.length ~/ 2];
  final threshold = math.max(.005, 3 * median);
  final settings = analysis?.settings ?? const <String, Object?>{};
  double? real(String key) => (settings[key] as num?)?.toDouble();
  int? integer(String key) => (settings[key] as num?)?.toInt();
  final finite = input.length - nonFinite;
  final floor = real('probeMatchFloor');
  final firstMatch = real('probeMatchStart'), lastMatch = real('probeMatchEnd');
  return RecordingDiagnostics(
    sampleRate: rate,
    durationSeconds: input.length / rate,
    sampleCount: input.length,
    nonFiniteSamples: nonFinite,
    zeroSamples: zeros,
    clippedSamples: clipped,
    rms: finite == 0 ? null : math.sqrt(sumSquares / finite),
    probeLowHz: math.max(0, low),
    probeHighHz: math.min(rate / 2, high),
    probeBandFraction: totalEnergy > 0 ? bandEnergy / totalEnergy : null,
    // spectrum() uses sum(window)^2 normalization. Correct for the Hann
    // window's mean-square weight to express band power as signal RMS.
    probeBandRms: spectralWindows == 0
        ? null
        : math.sqrt(bandEnergy / spectralWindows * (2 * 1023 / (3 * 1024))),
    spectralWindows: spectralWindows,
    transientThreshold: threshold,
    transientsSeconds: [
      for (final w in windows)
        if (w.rms > threshold) w.time,
    ],
    probeMatchStart: real('probeMatchStart'),
    probeMatchEnd: real('probeMatchEnd'),
    startLagSamples: integer('startLagSamples'),
    endLagSamples: integer('endLagSamples'),
    reliableAlignment: floor == null || firstMatch == null || lastMatch == null
        ? null
        : analysis!.valid && firstMatch >= floor && lastMatch >= floor,
    transmitterOn: c.transmitterOn,
  );
}

class RecordingDiagnosticsPanel extends StatelessWidget {
  const RecordingDiagnosticsPanel({
    super.key,
    required this.summary,
    this.label = 'Current displayed recording',
  });
  final RecordingDiagnostics summary;
  final String label;

  @override
  Widget build(BuildContext context) {
    String number(double? value) =>
        value == null ? 'unavailable' : value.toStringAsPrecision(3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recording quality · $label',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          '${summary.durationSeconds.toStringAsFixed(2)} s · ${summary.sampleRate} Hz · RMS ${number(summary.rms)} full scale',
        ),
        Text(
          'Exact-zero samples: ${summary.zeroSamples}/${summary.sampleCount}${summary.exactlySilent ? ' (silent input)' : ''} · clipped samples: ${summary.clippedSamples} · non-finite: ${summary.nonFiniteSamples}',
        ),
        Text(
          'Nominal ${summary.probeLowHz.toStringAsFixed(0)}–${summary.probeHighHz.toStringAsFixed(0)} Hz band: ${summary.probeBandFraction == null ? 'fraction unavailable' : '${number(100 * summary.probeBandFraction!)}% of sampled spectral energy'}, estimated RMS ${number(summary.probeBandRms)} full scale (${summary.spectralWindows} sampled windows)${summary.transmitterOn ? ' (includes probe)' : ' (transmitter off)'}.',
        ),
        Text(
          'Candidate probe match start/end: ${number(summary.probeMatchStart)} / ${number(summary.probeMatchEnd)}; candidate lag: ${summary.startLagSamples ?? 'unavailable'} / ${summary.endLagSamples ?? 'unavailable'} samples. ${summary.reliableAlignment == true
              ? 'Alignment accepted.'
              : summary.reliableAlignment == false
              ? 'No reliable alignment.'
              : 'Alignment unavailable.'}',
        ),
        Text(
          'High-RMS 100 ms windows above ${number(summary.transientThreshold)} full scale, elapsed seconds: ${summary.transientsSeconds.isEmpty ? 'none flagged' : summary.transientsSeconds.map((x) => x.toStringAsFixed(2)).join(', ')}. A spike does not identify its cause.',
        ),
      ],
    );
  }
}

class TraceSeries {
  const TraceSeries(this.label, this.result);
  final String label;
  final AnalysisResult? result;
}

/// Time is elapsed since each capture began; captures are not synchronized.
class AlignedTrialTraces {
  const AlignedTrialTraces(this.series);
  final List<TraceSeries> series;
}

AlignedTrialTraces alignTrialTraces(Map<String, AnalysisResult?> results) =>
    AlignedTrialTraces([
      for (final entry in results.entries) TraceSeries(entry.key, entry.value),
    ]);

class TrialTraceComparisonPanel extends StatelessWidget {
  const TrialTraceComparisonPanel({super.key, required this.comparison});
  final AlignedTrialTraces comparison;
  static const _colors = [
    Colors.blue,
    Colors.deepOrange,
    Colors.teal,
    Colors.purple,
  ];

  @override
  Widget build(BuildContext context) {
    final frames = [
      for (final series in comparison.series)
        if (series.result?.valid == true)
          ...series.result!.frames.where(
            (frame) =>
                frame.time.isFinite &&
                frame.movement.isFinite &&
                frame.time >= 0,
          ),
    ];
    final maxTime = frames.fold<double>(0, (v, f) => math.max(v, f.time));
    final maxValue = frames.fold<double>(
      0,
      (v, f) => math.max(v, f.movement.abs()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Trial traces', style: Theme.of(context).textTheme.titleMedium),
        const Text(
          'Elapsed seconds from each recording start; recordings are not synchronized. Normalized, detrended echo I/Q (dimensionless); gates and components may differ.',
        ),
        SizedBox(
          height: 180,
          width: double.infinity,
          child: CustomPaint(
            painter: _TracePainter(comparison.series),
            child: Semantics(label: 'Echo trace comparison by elapsed seconds'),
          ),
        ),
        Text(
          'Time: 0–${maxTime.toStringAsFixed(1)} s · vertical scale: ±${maxValue.toStringAsPrecision(3)} normalized units',
        ),
        for (var i = 0; i < comparison.series.length; i++)
          Builder(
            builder: (context) {
              final series = comparison.series[i], result = series.result;
              final available = result != null && result.valid;
              return Text(
                '${series.label}: ${available ? 'gate ${result.settings['traceGateMeters'] ?? '?'} m, component ${result.settings['traceComponent'] ?? '?'}, peak ${result.settings['peakHz'] ?? 'unavailable'} Hz, periodic fraction ${result.settings['periodicFraction'] ?? 'unavailable'}, RMS ${result.settings['periodicRms'] ?? 'unavailable'}' : 'trace unavailable${result == null || result.quality.isEmpty ? '' : ' (${result.quality.join('; ')})'}'}',
                style: TextStyle(color: _colors[i % _colors.length]),
              );
            },
          ),
        const Text(
          'Transmitter-off audio can be compared using its recording-quality metrics even when no coherent echo trace is available.',
        ),
      ],
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter(this.series);
  final List<TraceSeries> series;
  @override
  void paint(Canvas canvas, Size size) {
    final frames = [
      for (final s in series)
        if (s.result?.valid == true)
          ...s.result!.frames.where(
            (f) => f.time.isFinite && f.movement.isFinite && f.time >= 0,
          ),
    ];
    if (frames.isEmpty || size.width <= 0 || size.height <= 0) return;
    final maxTime = frames.fold<double>(0, (v, f) => math.max(v, f.time));
    final maxAbs = frames.fold<double>(
      0,
      (v, f) => math.max(v, f.movement.abs()),
    );
    if (maxTime <= 0 || maxAbs <= 0) return;
    final axis = Paint()
      ..color = Colors.grey
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      axis,
    );
    for (var i = 0; i < series.length; i++) {
      final result = series[i].result;
      if (result == null || !result.valid) continue;
      final paint = Paint()
        ..color = TrialTraceComparisonPanel
            ._colors[i % TrialTraceComparisonPanel._colors.length]
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final path = Path();
      var started = false;
      for (final frame in result.frames) {
        if (!frame.time.isFinite ||
            !frame.movement.isFinite ||
            frame.time < 0) {
          started = false;
          continue;
        }
        final x = frame.time / maxTime * size.width;
        final y = size.height / 2 - frame.movement / maxAbs * size.height * .45;
        if (started) {
          path.lineTo(x, y);
        } else {
          path.moveTo(x, y);
          started = true;
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TracePainter oldDelegate) =>
      oldDelegate.series != series;
}
