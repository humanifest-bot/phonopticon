import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/domain/experiment.dart';
import 'package:phonopticon/export/artifacts.dart';

AnalysisFrame frame(double time) =>
    AnalysisFrame(time, const [1e-12], .1, null);

AnalysisResult result(List<AnalysisFrame> frames) => AnalysisResult(
  axis: const [.6],
  frames: frames,
  quality: const [],
  settings: const {'breathingAlgorithm': 'fixture'},
  axisLabel: 'Equivalent range (m)',
  threshold: 0,
);

void main() {
  test(
    'SVG heatmap places frames at elapsed times and leaves dropped frames blank',
    () {
      final svg = spectrumSvg(result([frame(1), frame(2), frame(4), frame(5)]));
      final matches = RegExp(
        r'<rect x="([^"]+)" y="[^"]+" width="([^"]+)"',
      ).allMatches(svg).toList();
      expect(matches, hasLength(4));
      final x = [for (final match in matches) double.parse(match.group(1)!)];
      final widths = [
        for (final match in matches) double.parse(match.group(2)!),
      ];
      expect(x[0], closeTo(132, 1e-9));
      expect(x[1] + widths[1], closeTo(420, 1e-9));
      expect(x[2], closeTo(564, 1e-9));
      expect(x[3] + widths[3], closeTo(780, 1e-9));
      expect(svg, contains('Time (seconds), 0–5.00'));
    },
  );

  test(
    'SVG movement trace breaks instead of interpolating over absent frames',
    () {
      final svg = movementSvg(result([frame(1), frame(2), frame(4), frame(5)]));
      final points = RegExp(
        r'<polyline points="([^"]+)"',
      ).allMatches(svg).map((m) => m.group(1)!).toList();
      expect(points, hasLength(2));
      expect(points[0], startsWith('184.00,'));
      expect(points[0], contains('328.00,'));
      expect(points[1], startsWith('616.00,'));
      expect(points[1], contains('760.00,'));
    },
  );

  test(
    'single and invalid timestamps produce no invented duration or NaN geometry',
    () {
      final single = result([frame(0)]);
      expect(movementSvg(single), contains('<circle'));
      expect(spectrumSvg(single), contains('width="1.0"'));
      expect(movementSvg(single), isNot(contains('NaN')));
      expect(spectrumSvg(single), isNot(contains('NaN')));
      final invalid = result([frame(double.nan), frame(-1)]);
      expect(movementSvg(invalid), contains('no valid elapsed-time trace'));
      expect(
        spectrumSvg(invalid),
        contains('no reliable elapsed-time spectrum'),
      );
    },
  );
}
