import 'dart:math' as math;
import '../domain/experiment.dart';

/// Infer the nominal cadence from the lower median of positive time gaps.
/// A missing cadence is reported as null rather than guessed.
double? nominalFrameInterval(List<AnalysisFrame> frames) {
  final times = [
    for (final frame in frames)
      if (frame.time.isFinite && frame.time >= 0) frame.time,
  ]..sort();
  final gaps = <double>[];
  for (var i = 1; i < times.length; i++) {
    final gap = times[i] - times[i - 1];
    if (gap > 1e-12) gaps.add(gap);
  }
  if (gaps.isEmpty) return null;
  gaps.sort();
  return gaps[(gaps.length - 1) ~/ 2];
}

/// Split at invalid/non-increasing times, invalid values, and gaps larger than
/// 1.5 times the inferred cadence. No interpolation crosses such gaps.
List<List<AnalysisFrame>> elapsedTraceSegments(List<AnalysisFrame> frames) {
  final interval = nominalFrameInterval(frames);
  final segments = <List<AnalysisFrame>>[];
  List<AnalysisFrame>? current;
  double? previous;
  for (final frame in frames) {
    if (!frame.time.isFinite || frame.time < 0 || !frame.movement.isFinite) {
      current = null;
      previous = null;
      continue;
    }
    final delta = previous == null ? null : frame.time - previous;
    if (current == null ||
        delta == null ||
        delta <= 0 ||
        (interval != null && delta > 1.5 * interval + 1e-12)) {
      current = <AnalysisFrame>[];
      segments.add(current);
    }
    current.add(frame);
    previous = frame.time;
  }
  return segments;
}

/// Each heatmap cell's time extent in seconds since capture began. A longer
/// gap remains empty. Invalid times are omitted; a single distinct timestamp
/// has no inferred duration and is represented by a zero-width span.
List<({int frameIndex, double startSeconds, double endSeconds})>
heatmapTimeCells(List<AnalysisFrame> frames) {
  final times = [
    for (final frame in frames)
      if (frame.time.isFinite && frame.time >= 0) frame.time,
  ]..sort();
  if (times.isEmpty) return [];
  final duration = times.last;
  final halfWidth = (nominalFrameInterval(frames) ?? 0) / 2;
  return [
    for (var i = 0; i < frames.length; i++)
      if (frames[i].time.isFinite && frames[i].time >= 0)
        (
          frameIndex: i,
          startSeconds: math.max(0, frames[i].time - halfWidth),
          endSeconds: math.min(duration, frames[i].time + halfWidth),
        ),
  ];
}
