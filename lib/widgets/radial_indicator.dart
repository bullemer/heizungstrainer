import 'dart:math';
import 'package:flutter/material.dart';

/// A custom-painted radial/circular progress indicator that displays
/// hot water tank temperature relative to a target temperature.
class RadialTemperatureIndicator extends StatelessWidget {
  final double currentTemp;
  final double targetTemp;
  final double size;
  final Color accentColor;
  final bool isDisconnected;

  const RadialTemperatureIndicator({
    super.key,
    required this.currentTemp,
    this.targetTemp = 55.0,
    this.size = 120,
    required this.accentColor,
    this.isDisconnected = false,
  });

  @override
  Widget build(BuildContext context) {
    final double progress = (targetTemp > 0 && !isDisconnected)
        ? (currentTemp / targetTemp).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RadialTemperaturePainter(
          progress: progress,
          accentColor: accentColor,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isDisconnected ? '—' : currentTemp.toStringAsFixed(1),
                style: TextStyle(
                  color: isDisconnected ? const Color(0xFF9E9EA8) : Colors.white,
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              if (!isDisconnected)
                Text(
                  '°C',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: size * 0.12,
                    height: 1.0,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadialTemperaturePainter extends CustomPainter {
  final double progress;
  final Color accentColor;

  _RadialTemperaturePainter({
    required this.progress,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double strokeWidth = 9.0;
    final double radius = (size.shortestSide - strokeWidth) / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);

    final Rect arcRect = Rect.fromCircle(center: center, radius: radius);

    // Background track
    final Paint trackPaint = Paint()
      ..color = const Color(0xFF2A2A32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc — starts at top (-pi/2) and sweeps clockwise
    if (progress > 0) {
      final Paint arcPaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final double sweepAngle = 2 * pi * progress;
      canvas.drawArc(arcRect, -pi / 2, sweepAngle, false, arcPaint);
    }
  }

  @override
  bool shouldRepaint(_RadialTemperaturePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accentColor != accentColor;
  }
}
