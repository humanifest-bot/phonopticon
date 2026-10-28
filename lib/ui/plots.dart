import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/experiment.dart';

class TrialPlot extends StatelessWidget {
  const TrialPlot({super.key, required this.result, this.movement = false});
  final AnalysisResult result;
  final bool movement;
  @override
  Widget build(BuildContext context) => Semantics(
    label: movement
        ? 'Movement score over time. Threshold ${result.threshold}.'
        : '${result.axisLabel} over time. See frame inspector for numerical values.',
    child: SizedBox(
      height: movement ? 160 : 290,
      width: double.infinity,
      child: CustomPaint(painter: _PlotPainter(result, movement)),
    ),
  );
}

class _PlotPainter extends CustomPainter {
  _PlotPainter(this.r, this.movement);
  final AnalysisResult r;
  final bool movement;
  void text(
    Canvas canvas,
    String text,
    Offset position, {
    Color color = const Color(0xff526377),
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 11, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, position);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (r.frames.isEmpty || r.axis.isEmpty) return;
    final box = Rect.fromLTRB(56, 12, size.width - 12, size.height - 36);
    if (box.width <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(6)),
      Paint()..color = const Color(0xff0c1b30),
    );
    final duration = r.frames.last.time;
    if (!movement) {
      final low = r.axisLabel.startsWith('Doppler') ? -120.0 : -180.0;
      for (var t = 0; t < r.frames.length; t++) {
        for (var k = 0; k < r.axis.length; k++) {
          final db =
              10 * math.log(math.max(1e-24, r.frames[t].power[k])) / math.ln10;
          final v = ((db - low) / 100).clamp(0.0, 1.0);
          canvas.drawRect(
            Rect.fromLTWH(
              box.left + t / r.frames.length * box.width,
              box.bottom - (k + 1) / r.axis.length * box.height,
              box.width / r.frames.length + 0.5,
              box.height / r.axis.length + 0.5,
            ),
            Paint()
              ..color = Color.fromARGB(
                255,
                (15 + 225 * v).round(),
                (25 + 170 * v).round(),
                (45 + 45 * v).round(),
              ),
          );
        }
      }
      text(canvas, r.axis.last.toStringAsFixed(1), Offset(0, box.top));
      text(canvas, r.axis.first.toStringAsFixed(1), Offset(0, box.bottom - 12));
      text(
        canvas,
        'Power: ${low.toInt()} to ${(low + 100).toInt()} dB re 1 sample²',
        Offset(box.left, size.height - 14),
      );
    } else {
      final maxScore = math.max(
        r.threshold * 2,
        r.frames.map((f) => f.movement).reduce(math.max),
      );
      final thresholdY = box.bottom - r.threshold / maxScore * box.height;
      canvas.drawLine(
        Offset(box.left, thresholdY),
        Offset(box.right, thresholdY),
        Paint()
          ..color = const Color(0xffe6ad62)
          ..strokeWidth = 1,
      );
      text(canvas, r.threshold.toStringAsFixed(2), Offset(0, thresholdY - 5));
      text(canvas, maxScore.toStringAsFixed(2), Offset(0, box.top));
      final path = Path();
      for (var i = 0; i < r.frames.length; i++) {
        final f = r.frames[i];
        final x = box.left + f.time / duration * box.width,
            y = box.bottom - f.movement / maxScore * box.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xff67e1ce)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
    text(canvas, '0 s', Offset(box.left, box.bottom + 6));
    text(
      canvas,
      '${duration.toStringAsFixed(2)} s',
      Offset(box.right - 40, box.bottom + 6),
    );
  }

  @override
  bool shouldRepaint(covariant _PlotPainter oldDelegate) =>
      oldDelegate.r != r || oldDelegate.movement != movement;
}
