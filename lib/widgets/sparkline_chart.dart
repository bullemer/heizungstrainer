/// Custom-painted sparkline chart for temperature trend visualization.
///
/// Renders a minimal, animated line chart with gradient fill suitable
/// for embedding inside compact sensor cards.
library;

import 'package:flutter/material.dart';

/// A lightweight sparkline chart widget that draws a series of data points
/// as a smooth line with an optional gradient fill.
///
/// Designed for compact use inside dashboard cards — no axes, labels, or
/// grid lines. Just a clean trend line.
class SparklineChart extends StatelessWidget {
  /// The data points to plot. At least 2 points needed for a line.
  final List<double> data;

  /// The color of the sparkline stroke.
  final Color lineColor;

  /// Optional gradient fill below the line.
  final Color? fillColor;

  /// Stroke width of the line.
  final double strokeWidth;

  /// Height of the chart area.
  final double height;

  const SparklineChart({
    super.key,
    required this.data,
    required this.lineColor,
    this.fillColor,
    this.strokeWidth = 2.0,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) {
      return SizedBox(height: height);
    }

    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _SparklinePainter(
          data: data,
          lineColor: lineColor,
          fillColor: fillColor ?? lineColor.withValues(alpha: 0.15),
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final Color fillColor;
  final double strokeWidth;

  _SparklinePainter({
    required this.data,
    required this.lineColor,
    required this.fillColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final minVal = data.reduce((a, b) => a < b ? a : b);
    final maxVal = data.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;

    // Add 10% padding to range, minimum 0.5 to avoid flat lines
    final paddedRange = range < 0.5 ? 0.5 : range * 1.2;
    final midVal = (minVal + maxVal) / 2;
    final effectiveMin = midVal - paddedRange / 2;

    final stepX = size.width / (data.length - 1);

    // Build path
    final linePath = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedY = (data[i] - effectiveMin) / paddedRange;
      final y = size.height - (normalizedY * size.height);

      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        // Smooth curve using cubic bezier
        final prevX = (i - 1) * stepX;
        final prevNormY = (data[i - 1] - effectiveMin) / paddedRange;
        final prevY = size.height - (prevNormY * size.height);
        final controlX = (prevX + x) / 2;

        linePath.cubicTo(controlX, prevY, controlX, y, x, y);
        fillPath.cubicTo(controlX, prevY, controlX, y, x, y);
      }
    }

    // Close fill path
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Draw gradient fill
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          fillColor,
          fillColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // Draw current value dot at the end
    final lastX = (data.length - 1) * stepX;
    final lastNormY = (data.last - effectiveMin) / paddedRange;
    final lastY = size.height - (lastNormY * size.height);

    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastX, lastY), strokeWidth * 1.8, dotPaint);

    // Draw glow around dot
    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastX, lastY), strokeWidth * 3, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.lineColor != lineColor;
  }
}

/// Returns a color representing the "heat level" of a temperature value.
///
/// Maps temperature to a gradient from cold blue through green to hot red.
Color getTemperatureColor(double tempCelsius) {
  if (tempCelsius <= 0) return const Color(0xFF42A5F5); // Cold blue
  if (tempCelsius <= 10) return const Color(0xFF66BB6A); // Cool green
  if (tempCelsius <= 20) return const Color(0xFF8BC34A); // Mild green
  if (tempCelsius <= 30) return const Color(0xFFFFA726); // Warm orange
  if (tempCelsius <= 45) return const Color(0xFFFF7043); // Hot orange-red
  if (tempCelsius <= 60) return const Color(0xFFEF5350); // Hot red
  return const Color(0xFFD32F2F); // Very hot dark red
}

/// Returns a color for flow/supply temperature (higher expected range).
Color getFlowTemperatureColor(double tempCelsius) {
  if (tempCelsius <= 25) return const Color(0xFF42A5F5);
  if (tempCelsius <= 35) return const Color(0xFF66BB6A);
  if (tempCelsius <= 45) return const Color(0xFFFFA726);
  if (tempCelsius <= 55) return const Color(0xFFFF7043);
  if (tempCelsius <= 70) return const Color(0xFFEF5350);
  return const Color(0xFFD32F2F);
}
