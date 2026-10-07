import 'package:heizungstrainer/utils/number_format.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:heizungstrainer/services/heating_curve_model.dart';

/// The heating curve as stored in the controller (solid, with its six
/// points – the same view as the controller's own display, based on 20 °C
/// room temperature) and, when the comfort setpoint differs from 20 °C, the
/// curve that is actually in effect (thin dashed). If [simulatedSetpoint]
/// differs from [roomSetpoint], the curve at that setpoint (blue dashed).
/// Marks the current outdoor temperature.
class ControllerCurveChart extends StatelessWidget {
  final ControllerHeatingCurve curve;
  final double roomSetpoint;
  final double? simulatedSetpoint;
  final double? outdoorTemp;
  final double height;

  /// Grey dashed reference: Danfoss factory curve at the same room setpoint.
  final bool showFactoryCurve;

  /// Green band: EnergieSchweiz guide values for this building type
  /// (defined for 20 °C room temperature).
  final BuildingReference? reference;

  static const currentColor = Color(0xFFFFA726);
  static const simulatedColor = Color(0xFF42A5F5);
  static const factoryColor = Color(0xFF9E9EA8);
  static const referenceColor = Color(0xFF66BB6A);
  static const _grid = Color(0xFF3A3A44);

  const ControllerCurveChart({
    super.key,
    required this.curve,
    required this.roomSetpoint,
    this.simulatedSetpoint,
    this.outdoorTemp,
    this.height = 230,
    this.showFactoryCurve = true,
    this.reference,
  });

  bool get showsSimulation =>
      simulatedSetpoint != null && (simulatedSetpoint! - roomSetpoint).abs() >= 0.25;

  @override
  Widget build(BuildContext context) => SizedBox(height: height, child: _chart());

  static const double _minX = -30;
  static const double _maxX = 20;

  /// Effective curve shown separately only if it visibly differs from the
  /// stored (20 °C) curve.
  bool get showsEffective =>
      (roomSetpoint - ControllerHeatingCurve.referenceRoomTemp).abs() >= 0.25;

  static String _fmt(double v) => v.fixed(1);

  Widget _chart() {
    const base = ControllerHeatingCurve.referenceRoomTemp;
    final room = roomSetpoint;
    final sim = simulatedSetpoint ?? roomSetpoint;
    List<FlSpot> line(ControllerHeatingCurve c, double setpoint) => [
          for (var x = _minX; x <= _maxX; x += 1) FlSpot(x, c.flowAt(x, setpoint)),
        ];
    final stored = line(curve, base);
    final effective = line(curve, room);
    final simulated = line(curve, sim);
    final factory = line(danfossFactoryCurve, base);
    final ref = reference;
    final refLow = ref == null ? <FlSpot>[] : [for (var x = _minX; x <= _maxX; x += 1) FlSpot(x, ref.lowAt(x))];
    final refHigh = ref == null ? <FlSpot>[] : [for (var x = _minX; x <= _maxX; x += 1) FlSpot(x, ref.highAt(x))];
    final pointXs = curve.outdoorTemps.toSet();

    // Bars in drawing order; labels feed the tooltip.
    final bars = <(LineChartBarData, String?)>[
      if (ref != null) ...[
        (LineChartBarData(spots: refLow, color: referenceColor.withValues(alpha: 0.5), barWidth: 1, dotData: const FlDotData(show: false)), null),
        (LineChartBarData(spots: refHigh, color: referenceColor.withValues(alpha: 0.5), barWidth: 1, dotData: const FlDotData(show: false)), 'Richtwert'),
      ],
      if (showFactoryCurve)
        (
          LineChartBarData(
            spots: factory,
            color: factoryColor.withValues(alpha: 0.8),
            barWidth: 1.5,
            dashArray: [3, 4],
            dotData: const FlDotData(show: false),
          ),
          'Werkseinstellung'
        ),
      (
        LineChartBarData(
          spots: stored,
          color: currentColor,
          barWidth: 3,
          dotData: FlDotData(
            show: true,
            checkToShowDot: (spot, _) => pointXs.contains(spot.x),
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
              radius: 3.5,
              color: currentColor,
              strokeWidth: 1.5,
              strokeColor: const Color(0xFF2A2A32),
            ),
          ),
        ),
        'Regler'
      ),
      if (showsEffective)
        (
          LineChartBarData(
            spots: effective,
            color: currentColor.withValues(alpha: 0.7),
            barWidth: 1.5,
            dashArray: [2, 3],
            dotData: const FlDotData(show: false),
          ),
          'Wirksam bei ${_fmt(room)} °C'
        ),
      if (showsSimulation)
        (
          LineChartBarData(
            spots: simulated,
            color: simulatedColor,
            barWidth: 2.5,
            dashArray: [6, 4],
            dotData: const FlDotData(show: false),
          ),
          'Simulation ${_fmt(sim)} °C'
        ),
    ];

    // Scale to the user's curves (like the controller's own view); the much
    // higher factory curve is clipped instead of squashing everything.
    final all = [...stored, ...effective, if (showsSimulation) ...simulated, ...refLow, ...refHigh].map((s) => s.y);
    final minY = (all.reduce((a, b) => a < b ? a : b) / 5).floor() * 5 - 5.0;
    final maxY = (all.reduce((a, b) => a > b ? a : b) / 5).ceil() * 5 + 5.0;
    const axis = TextStyle(color: Color(0xFF9E9EA8), fontSize: 10);

    return LineChart(LineChartData(
      minX: _minX,
      maxX: _maxX,
      clipData: const FlClipData.all(),
      minY: minY,
      maxY: maxY,
      gridData: FlGridData(
        horizontalInterval: 5,
        verticalInterval: 5,
        getDrawingHorizontalLine: (_) => const FlLine(color: _grid, strokeWidth: 0.5),
        getDrawingVerticalLine: (_) => const FlLine(color: _grid, strokeWidth: 0.5),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          axisNameWidget: const Text('Vorlauf °C', style: axis),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 5,
            getTitlesWidget: (v, _) => Text('${v.toInt()}', style: axis),
          ),
        ),
        bottomTitles: AxisTitles(
          axisNameWidget: const Text('Außentemperatur °C', style: axis),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: 10,
            getTitlesWidget: (v, _) => Text('${v.toInt()}', style: axis),
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      // Index 0/1 = guide band edges (filled between), drawn first = behind.
      betweenBarsData: [
        if (ref != null)
          BetweenBarsData(fromIndex: 0, toIndex: 1, color: referenceColor.withValues(alpha: 0.16)),
      ],
      lineBarsData: [for (final b in bars) b.$1],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => const Color(0xF0202028),
          fitInsideHorizontally: true,
          maxContentWidth: 240,
          fitInsideVertically: true,
          getTooltipItems: (touched) {
            final items = <LineTooltipItem?>[];
            var header = true;
            for (final t in touched) {
              final label = bars[t.barIndex].$2;
              if (label == null) {
                items.add(null);
                continue;
              }
              final value = label == 'Richtwert' && ref != null
                  ? '${_fmt(ref.lowAt(t.x))}–${_fmt(t.y)} °C'
                  : '${_fmt(t.y)} °C';
              items.add(LineTooltipItem(
                header ? '${t.x.fixed(0)} °C außen\n' : '',
                const TextStyle(color: Color(0xFFBDBDC7), fontSize: 10.5),
                textAlign: TextAlign.left,
                children: [
                  TextSpan(
                    text: '$label: $value',
                    style: TextStyle(
                      color: bars[t.barIndex].$1.color ?? Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ));
              header = false;
            }
            return items;
          },
        ),
      ),
      extraLinesData: ExtraLinesData(verticalLines: [
        if (outdoorTemp != null)
          VerticalLine(
            x: outdoorTemp!.clamp(_minX, _maxX).toDouble(),
            color: Colors.white.withValues(alpha: 0.35),
            strokeWidth: 1,
            dashArray: [4, 4],
            label: VerticalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: const TextStyle(color: Color(0xFFBDBDC7), fontSize: 10),
              labelResolver: (_) => 'jetzt',
            ),
          ),
      ]),
    ));
  }
}
