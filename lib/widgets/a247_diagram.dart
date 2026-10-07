import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:heizungstrainer/models/live_snapshot.dart';
import 'package:heizungstrainer/utils/number_format.dart';

/// Plant diagram for Danfoss application A247.1 (district heating with a
/// heating circuit and DHW charging), modelled on the Danfoss portal's
/// "Application" view: measured values in white, controller targets in blue
/// brackets, pumps orange when running, valves with their motion.
class A247Diagram extends StatelessWidget {
  const A247Diagram({super.key, required this.snapshot});

  final LiveSnapshot snapshot;

  static const logicalSize = Size(1000, 640);

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: logicalSize.width / logicalSize.height,
        child: CustomPaint(painter: _A247Painter(snapshot), size: Size.infinite),
      );
}

class _A247Painter extends CustomPainter {
  _A247Painter(this.s);

  final LiveSnapshot s;

  static const red = Color(0xFFE53935);
  static const blue = Color(0xFF1E88E5);
  static const green = Color(0xFF43A047);
  static const text = Color(0xFFECECF0);
  static const muted = Color(0xFF9E9EA8);
  static const target = Color(0xFF64B5F6);
  static const on = Color(0xFFFFA726);
  static const frame = Color(0xFFBDBDC7);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / A247Diagram.logicalSize.width;
    canvas.scale(k);

    // ── pipes ──
    final pipe = Paint()
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    void line(List<Offset> pts, Color c, {bool dashed = false}) {
      pipe.color = c;
      if (!dashed) {
        canvas.drawPath(Path()..addPolygon(pts, false), pipe);
        return;
      }
      for (var i = 0; i < pts.length - 1; i++) {
        final a = pts[i], b = pts[i + 1];
        final len = (b - a).distance;
        for (var d = 0.0; d < len; d += 18) {
          canvas.drawLine(Offset.lerp(a, b, d / len)!, Offset.lerp(a, b, math.min(d + 10, len) / len)!, pipe);
        }
      }
    }

    // district heating supply (red) and branches to both exchangers
    line([const Offset(60, 160), const Offset(560, 160)], red);
    line([const Offset(230, 160), const Offset(230, 440), const Offset(560, 440)], red);
    // primary returns (blue) via S5/M2 and S2/M1
    line([const Offset(560, 290), const Offset(60, 290)], blue);
    line([const Offset(560, 560), const Offset(110, 560), const Offset(110, 290)], blue);
    // heating circuit ①
    line([const Offset(640, 160), const Offset(985, 160)], red);
    line([const Offset(985, 290), const Offset(640, 290)], blue);
    line([const Offset(985, 160), const Offset(985, 185)], red);
    line([const Offset(985, 255), const Offset(985, 290)], blue);
    // DHW charging ②
    line([const Offset(640, 440), const Offset(760, 440), const Offset(760, 395), const Offset(985, 395)], red);
    line([const Offset(850, 395), const Offset(850, 425)], red);
    line([const Offset(985, 395), const Offset(985, 500), const Offset(915, 500)], red, dashed: true);
    line([const Offset(640, 560), const Offset(780, 560), const Offset(780, 615), const Offset(985, 615)], green);
    line([const Offset(850, 590), const Offset(850, 615)], green);

    // flow arrows at the district heating connection
    _triangle(canvas, const Offset(40, 160), red, pointsRight: true);
    _triangle(canvas, const Offset(40, 290), blue, pointsRight: false);
    _triangle(canvas, const Offset(995, 615), green, pointsRight: false);

    // ── heat exchangers ──
    _exchanger(canvas, const Rect.fromLTWH(560, 130, 80, 190));
    _exchanger(canvas, const Rect.fromLTWH(560, 410, 80, 180));

    // ── radiator (circuit 1) and tank (circuit 2) ──
    final framePaint = Paint()
      ..color = frame
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final radiator = const Rect.fromLTWH(880, 185, 105, 70);
    canvas.drawRRect(RRect.fromRectAndRadius(radiator, const Radius.circular(6)), framePaint);
    for (var x = radiator.left + 12; x < radiator.right - 6; x += 12) {
      canvas.drawLine(Offset(x, radiator.top + 8), Offset(x, radiator.bottom - 8), framePaint..strokeWidth = 1.5);
    }
    framePaint.strokeWidth = 3;
    _circled(canvas, '1', const Offset(930, 280));
    final tank = const Rect.fromLTWH(790, 425, 125, 165);
    canvas.drawRRect(RRect.fromRectAndRadius(tank, const Radius.circular(40)), framePaint);
    _circled(canvas, '2', const Offset(955, 580));
    _label(canvas, 'Warmwasser', const Offset(880, 366), size: 15, color: muted);

    // ── pumps and valves ──
    _pump(canvas, const Offset(800, 160), 'P1', s.p1, pointsRight: true);
    _pump(canvas, const Offset(710, 560), 'P2', s.p2, pointsRight: false);
    _pump(canvas, const Offset(950, 500), 'P3', s.p3, pointsRight: false);
    _valve(canvas, const Offset(340, 290), 'M2', s.m2);
    _valve(canvas, const Offset(340, 560), 'M1', s.m1);

    // ── sensors: measured (white) and target (blue) ──
    _sensor(canvas, 3, const Offset(690, 160), const Offset(655, 82));
    _sensor(canvas, 5, const Offset(470, 290), const Offset(420, 212));
    _sensor(canvas, 4, const Offset(690, 440), const Offset(655, 362), labelAbove: true);
    _sensor(canvas, 2, const Offset(470, 560), const Offset(420, 482));
    _sensor(canvas, 6, const Offset(808, 462), const Offset(806, 462), dot: true, compact: true);
    _sensor(canvas, 8, const Offset(808, 545), const Offset(806, 545), dot: true, compact: true);

    // ── header: outdoor, controller time, alarm output ──
    final outdoor = s.sensors[1];
    _label(canvas, 'Außen S1', const Offset(40, 28), size: 18, color: muted, bold: true);
    _label(canvas, outdoor == null ? '--' : '${outdoor.fixed(1)} °C', const Offset(40, 56), size: 24, color: text);
    if (s.controllerTime != null) {
      final t = s.controllerTime!;
      _label(canvas, 'Reglerzeit', const Offset(380, 28), size: 16, color: muted);
      _label(
          canvas,
          '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} '
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
          const Offset(380, 50),
          size: 20,
          color: text);
    }
    _label(canvas, s.alarmOutput ? 'A1 ALARM' : 'A1 —', const Offset(850, 40),
        size: 20, color: s.alarmOutput ? red : muted, bold: s.alarmOutput);
  }

  void _circled(Canvas c, String n, Offset center) {
    c.drawCircle(
        center,
        17,
        Paint()
          ..color = text
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
    _label(c, n, center + const Offset(-6, -13), size: 22, color: text, bold: true);
  }

  void _triangle(Canvas c, Offset at, Color color, {required bool pointsRight}) {
    final d = pointsRight ? 1.0 : -1.0;
    c.drawPath(
      Path()
        ..moveTo(at.dx - 18 * d, at.dy - 20)
        ..lineTo(at.dx + 18 * d, at.dy)
        ..lineTo(at.dx - 18 * d, at.dy + 20)
        ..close(),
      Paint()..color = color,
    );
  }

  void _exchanger(Canvas c, Rect r) {
    c.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(12)),
        Paint()
          ..color = const Color(0xFF1E1E24)
          ..style = PaintingStyle.fill);
    c.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(12)),
        Paint()
          ..color = frame
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    for (final (x, color) in [(r.left + 25, red), (r.left + 55, blue)]) {
      final path = Path()..moveTo(x, r.top + 15);
      var left = true;
      for (var y = r.top + 15; y < r.bottom - 25; y += 30) {
        path.lineTo(x + (left ? -12 : 12), y + 15);
        left = !left;
      }
      path.lineTo(x, r.bottom - 15);
      c.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
  }

  void _pump(Canvas c, Offset at, String name, bool running, {required bool pointsRight}) {
    c.drawCircle(at, 24, Paint()..color = const Color(0xFF1E1E24));
    c.drawCircle(
        at,
        24,
        Paint()
          ..color = running ? on : frame
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    final d = pointsRight ? 1.0 : -1.0;
    c.drawPath(
      Path()
        ..moveTo(at.dx - 12 * d, at.dy - 15)
        ..lineTo(at.dx + 16 * d, at.dy)
        ..lineTo(at.dx - 12 * d, at.dy + 15)
        ..close(),
      Paint()..color = running ? on : const Color(0xFF6E6E7A),
    );
    _label(c, name, at + const Offset(-14, -52), size: 20, color: text, bold: true);
    _label(c, running ? 'an' : 'aus', at + const Offset(-12, 28), size: 15, color: running ? on : muted);
  }

  void _valve(Canvas c, Offset at, String name, ValveMotion motion) {
    final p = Paint()..color = const Color(0xFF1E1E24);
    final stroke = Paint()
      ..color = frame
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final bow = Path()
      ..moveTo(at.dx - 28, at.dy - 18)
      ..lineTo(at.dx + 28, at.dy + 18)
      ..lineTo(at.dx + 28, at.dy - 18)
      ..lineTo(at.dx - 28, at.dy + 18)
      ..close();
    c.drawPath(bow, p);
    c.drawPath(bow, stroke);
    c.drawLine(at, at + const Offset(0, -30), stroke);
    c.drawCircle(at + const Offset(0, -38), 9, p);
    c.drawCircle(at + const Offset(0, -38), 9, stroke);
    _label(c, name, at + const Offset(-60, -66), size: 20, color: text, bold: true);
    final (label, color) = switch (motion) {
      ValveMotion.opening => ('öffnet', on),
      ValveMotion.closing => ('schließt', target),
      ValveMotion.idle => ('steht', muted),
    };
    final arrow = at + const Offset(-24, 36);
    if (motion == ValveMotion.idle) {
      c.drawLine(arrow + const Offset(-6, 8), arrow + const Offset(6, 8), Paint()..color = color..strokeWidth = 3);
    } else {
      final up = motion == ValveMotion.opening;
      c.drawPath(
        Path()
          ..moveTo(arrow.dx - 7, arrow.dy + (up ? 13 : 3))
          ..lineTo(arrow.dx + 7, arrow.dy + (up ? 13 : 3))
          ..lineTo(arrow.dx, arrow.dy + (up ? 3 : 13))
          ..close(),
        Paint()..color = color,
      );
    }
    _label(c, label, at + const Offset(-12, 30), size: 16, color: color);
  }

  void _sensor(Canvas c, int n, Offset at, Offset labelAt,
      {bool labelAbove = false, bool dot = false, bool compact = false}) {
    c.drawCircle(at, 9, Paint()..color = text);
    final measured = s.sensors[n];
    final ref = s.references[n];
    final value = measured == null ? '--' : '${measured.fixed(1)} °C';
    if (compact) {
      _label(c, 'S$n $value', labelAt + const Offset(12, -10), size: 15, color: text, bold: true);
      if (ref != null) _label(c, '(${ref.fixed(1)}) °C', labelAt + const Offset(30, 8), size: 14, color: target);
      return;
    }
    _label(c, value, labelAt, size: 20, color: text);
    if (ref != null) _label(c, '(${ref.fixed(1)}) °C', labelAt + const Offset(0, 24), size: 18, color: target);
    _label(c, 'S$n', at + const Offset(16, 10), size: 18, color: text, bold: true);
  }

  void _label(Canvas c, String s, Offset at, {required double size, required Color color, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontFamily: 'Roboto', color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at);
  }

  @override
  bool shouldRepaint(_A247Painter old) => old.s != s;
}
