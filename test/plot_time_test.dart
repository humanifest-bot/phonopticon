import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonopticon/domain/experiment.dart';
import 'package:phonopticon/ui/plots.dart';

AnalysisFrame frame(double time) => AnalysisFrame(time, const [1], 0, null);

void main() {
  test('heatmap cells use elapsed time and leave a dropped frame empty', () {
    // A regular 0.1 s sequence with the frame at 0.25 s absent.
    final cells = heatmapTimeCells([
      frame(.05),
      frame(.15),
      frame(.35),
      frame(.45),
    ]);
    expect(cells.map((cell) => cell.frameIndex), [0, 1, 2, 3]);
    expect(cells[0].startSeconds, closeTo(0, 1e-12));
    expect(cells[1].endSeconds, closeTo(.20, 1e-12));
    expect(cells[2].startSeconds, closeTo(.30, 1e-12));
    expect(cells[2].endSeconds, closeTo(.40, 1e-12));
    // The axis ends at the final frame's actual timestamp.
    expect(cells.last.endSeconds, closeTo(.45, 1e-12));
  });

  test(
    'trace segments break at dropped, invalid, and non-increasing times',
    () {
      final segments = elapsedTraceSegments([
        frame(.05),
        frame(.15),
        frame(.35),
        frame(.45),
        frame(double.nan),
        frame(.55),
        frame(.55),
        frame(.65),
      ]);
      expect(
        [
          for (final segment in segments)
            [for (final item in segment) item.time],
        ],
        [
          [.05, .15],
          [.35, .45],
          [.55],
          [.55, .65],
        ],
      );
    },
  );

  test(
    'single times, invalid times, duplicates and unsorted data are bounded',
    () {
      final single = heatmapTimeCells([frame(2)]);
      expect(single.single.startSeconds, 2);
      expect(single.single.endSeconds, 2);
      expect(heatmapTimeCells([frame(double.nan), frame(-1)]), isEmpty);
      final cells = heatmapTimeCells([
        frame(2),
        frame(1),
        frame(double.infinity),
        frame(1),
        frame(1.5),
      ]);
      expect(cells.map((cell) => cell.frameIndex), [0, 1, 3, 4]);
      expect(
        cells.every((cell) => cell.startSeconds >= 0 && cell.endSeconds <= 2),
        isTrue,
      );
      expect(cells[0].startSeconds, closeTo(1.75, 1e-12));
      expect(cells[0].endSeconds, 2);
    },
  );

  testWidgets('the rendered heatmap leaves a missing-time interval dark', (
    tester,
  ) async {
    final key = GlobalKey();
    final result = AnalysisResult(
      axis: const [.6],
      frames: [frame(.05), frame(.15), frame(.35), frame(.45)],
      quality: const [],
      settings: const {},
      axisLabel: 'Equivalent range (m)',
      threshold: 0,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 400, child: TrialPlot(result: result)),
          ),
        ),
      ),
    );
    await tester.pump();
    final colors = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      List<int> colorAt(int x) {
        final offset = (100 * image.width + x) * 4;
        return [for (var i = 0; i < 3; i++) bytes!.getUint8(offset + i)];
      }

      // Plot bounds are 56..388 px. 0.15 s contains a frame; 0.25 s is absent.
      final present = (56 + .15 / .45 * 332).round();
      final missing = (56 + .25 / .45 * 332).round();
      final output = [colorAt(present), colorAt(missing)];
      image.dispose();
      return output;
    });
    expect(colors![1], [12, 27, 48]);
    expect(colors[0], isNot([12, 27, 48]));
  });

  testWidgets('the rendered movement trace does not bridge a dropped frame', (
    tester,
  ) async {
    final key = GlobalKey();
    AnalysisFrame point(double time, double movement) =>
        AnalysisFrame(time, const [1], movement, null);
    final result = AnalysisResult(
      axis: const [.6],
      frames: [point(.05, .2), point(.15, .1), point(.35, .1), point(.45, .1)],
      quality: const [],
      settings: const {'breathingAlgorithm': 'fixture'},
      axisLabel: 'Equivalent range (m)',
      threshold: 0,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 400,
              child: TrialPlot(result: result, movement: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final colors = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      List<int> colorAt(int x) {
        final offset = (40 * image.width + x) * 4;
        return [for (var i = 0; i < 3; i++) bytes!.getUint8(offset + i)];
      }

      final present = (56 + .40 / .45 * 332).round();
      final missing = (56 + .25 / .45 * 332).round();
      final output = [colorAt(present), colorAt(missing)];
      image.dispose();
      return output;
    });
    expect(colors![1], [12, 27, 48]);
    expect(colors[0], isNot([12, 27, 48]));
  });
}
