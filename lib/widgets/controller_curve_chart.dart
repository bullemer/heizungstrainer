import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:heizungstrainer/services/heating_curve_model.dart';

/// The controller's real heating curve (solid) and, if [simulatedSetpoint]
/// differs from [roomSetpoint], the curve the controller would use at that
/// setpoint (dashed). Marks the current outdoor temperature.
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

  Widget _chart() {
    final room = roomSetpoint;
    final sim = simulatedSetpoint ?? roomSetpoint;
    List<FlSpot> spots(double setpoint) => [
          for (var x = -20.0; x <= 20.0; x += 1) FlSpot(x, curve.flowAt(x, setpoint)),
        ];
    final current = spots(room);
    final simulated = spots(sim);
    final factory = [
      for (var x = -20.0; x <= 20.0; x += 1) FlSpot(x, danfossFactoryCurve.flowAt(x, room)),
    ];
    final ref = reference;
    final refLow = ref == null ? <FlSpot>[] : [for (var x = -20.0; x <= 20.0; x += 1) FlSpot(x, ref.lowAt(x))];
    final refHigh = ref == null ? <FlSpot>[] : [for (var x = -20.0; x <= 20.0; x += 1) FlSpot(x, ref.highAt(x))];
    final all = [
      ...current,
      ...simulated,
      if (showFactoryCurve) ...factory,
      ...refLow,
      ...refHigh,
    ].map((s) => s.y);
    final minY = (all.reduce((a, b) => a < b ? a : b) / 5).floor() * 5 - 5.0;
    final maxY = (all.reduce((a, b) => a > b ? a : b) / 5).ceil() * 5 + 5.0;
    const axis = TextStyle(color: Color(0xFF9E9EA8), fontSize: 10);

    return LineChart(LineChartData(
      minX: -20,
      maxX: 20,
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
            interval: 5,
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
      lineBarsData: [
        if (ref != null) ...[
          LineChartBarData(spots: refLow, color: referenceColor.withValues(alpha: 0.5), barWidth: 1, dotData: const FlDotData(show: false)),
          LineChartBarData(spots: refHigh, color: referenceColor.withValues(alpha: 0.5), barWidth: 1, dotData: const FlDotData(show: false)),
        ],
        if (showFactoryCurve)
          LineChartBarData(
            spots: factory,
            color: factoryColor.withValues(alpha: 0.8),
            barWidth: 1.5,
            dashArray: [3, 4],
            dotData: const FlDotData(show: false),
          ),
        LineChartBarData(spots: current, color: currentColor, barWidth: 3, dotData: const FlDotData(show: false)),
        if (showsSimulation)
          LineChartBarData(
            spots: simulated,
            color: simulatedColor,
            barWidth: 2.5,
            dashArray: [6, 4],
            dotData: const FlDotData(show: false),
          ),
      ],
      extraLinesData: ExtraLinesData(verticalLines: [
        if (outdoorTemp != null)
          VerticalLine(
            x: outdoorTemp!.clamp(-20, 20).toDouble(),
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
