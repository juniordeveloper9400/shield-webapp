import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// A small continuous line, curving from the first value to the last — a
/// trend read at a glance rather than a chart of points to parse, and never
/// a discrete point-to-point zigzag: every segment flows into the next the
/// way a real growth line should.
///
/// Drawn as a finished area graph rather than a bare line: a soft gradient
/// wash under the curve, a light baseline it rises off, and a haloed dot
/// marking where the line stands right now.
class TrendSparkline extends StatelessWidget {
  final List<int> values;
  final Color color;
  final double height;

  /// Whether the area under the curve is washed in [color]. Off for
  /// anywhere too small for the wash to read as anything but noise.
  final bool filled;

  /// One printed label per point in [values] — the amount each point stands
  /// for, e.g. what that year earned — set above the point it belongs to.
  /// Null leaves the line to speak for itself, the way the home card's
  /// strip-sized copy still does.
  final List<String>? valueLabels;

  const TrendSparkline({
    super.key,
    required this.values,
    this.color = AppColors.brandGreenDark,
    this.height = 60,
    this.filled = true,
    this.valueLabels,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _SparklinePainter(
          values: values,
          color: color,
          filled: filled,
          valueLabels: valueLabels,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> values;
  final Color color;
  final bool filled;
  final List<String>? valueLabels;

  const _SparklinePainter({
    required this.values,
    required this.color,
    required this.filled,
    this.valueLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) {
      return;
    }

    // A flat series (or a single value) still draws as a straight mid-line
    // rather than dividing by a zero range.
    final highest = values.reduce((a, b) => a > b ? a : b).toDouble();
    final lowest = values.reduce((a, b) => a < b ? a : b).toDouble();
    final range = highest == lowest ? 1.0 : highest - lowest;

    // Padding on every side so the line, and the halo around its end dot,
    // never touch the edge of the box they are drawn in. Labels need a
    // taller run of headroom above the line than the halo alone does.
    final topPad = valueLabels == null ? 0.16 : 0.34;
    const bottomPad = 0.2;
    final drawHeight = size.height * (1 - topPad - bottomPad);
    final baselineY = size.height * (1 - bottomPad);

    final n = values.length;
    final points = [
      for (var i = 0; i < n; i++)
        Offset(
          n == 1 ? size.width / 2 : size.width * i / (n - 1),
          baselineY - ((values[i] - lowest) / range) * drawHeight,
        ),
    ];

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) {
      line.lineTo(points.first.dx, points.first.dy);
    } else {
      // Quadratic curves through the midpoint of each pair, not straight
      // lines between the points themselves — the line stays smooth and
      // unbroken the whole way across, never showing its own joints.
      for (var i = 0; i < points.length - 1; i++) {
        final current = points[i];
        final next = points[i + 1];
        final mid = Offset(
          (current.dx + next.dx) / 2,
          (current.dy + next.dy) / 2,
        );
        line.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
      }
      line.lineTo(points.last.dx, points.last.dy);
    }

    if (filled) {
      // The same curve, closed down to a baseline and washed in a fading
      // gradient — an area graph, not just a line floating on its own.
      final area = Path.from(line)
        ..lineTo(points.last.dx, size.height)
        ..lineTo(points.first.dx, size.height)
        ..close();
      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
      );
      canvas.drawPath(
        area,
        Paint()..shader = gradient.createShader(Offset.zero & size),
      );

      // A light baseline the area rests on, so the wash reads as rising off
      // something rather than fading into empty space.
      canvas.drawLine(
        Offset(0, baselineY + 1),
        Offset(size.width, baselineY + 1),
        Paint()
          ..color = AppColors.border
          ..strokeWidth = 1,
      );
    }

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Where the line stands right now — a soft halo behind a solid dot,
    // ringed in white so it lifts off the line it sits on.
    canvas.drawCircle(points.last, 8, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawCircle(points.last, 4.5, Paint()..color = AppColors.white);
    canvas.drawCircle(points.last, 3.5, Paint()..color = color);

    final labels = valueLabels;
    if (labels != null) {
      // What each point actually earned, printed just above it — the
      // current point picked out in the line's own colour, every earlier
      // one in a quieter ink so the latest still reads first.
      for (var i = 0; i < n && i < labels.length; i++) {
        final isLast = i == n - 1;
        final painter = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(
              fontSize: 10,
              fontWeight: isLast ? FontWeight.w800 : FontWeight.w700,
              color: isLast ? color : AppColors.textBody,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final dx = points[i].dx - painter.width / 2;
        final clampedDx = dx.clamp(0.0, size.width - painter.width);
        final dy = points[i].dy - 12 - painter.height;
        painter.paint(canvas, Offset(clampedDx, dy < 0 ? 0 : dy));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.filled != filled ||
      oldDelegate.valueLabels != valueLabels;
}
