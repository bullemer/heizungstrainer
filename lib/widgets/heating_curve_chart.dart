/// Interactive heating curve line chart using fl_chart.
///
/// Plots the relationship between outdoor temperature (X) and
/// radiator flow target temperature (Y) based on the Danfoss
/// mathematical curve with the current parallel shift applied.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:heizungstrainer/services/heating_analytics_service.dart';

/// A premium heating curve chart that reacts to parallel shift changes.
///
/// Features:
/// - Dynamic curve line that shifts with the parallel shift register
/// - Reference "ideal" curve at shift=0 as a dashed line
/// - Current operating point plotted as a prominent glowing dot
/// - Dark theme styling matching the app palette
class HeatingCurveChart extends StatelessWidget {
  /// Current parallel shift value from the controller.
  final double parallelShift;

  /// Current outdoor temperature (S1) for the operating point.
  final double currentOutdoorTemp;

  /// Current flow temperature (S3) for the operating point.
  final double currentFlowTemp;

  const HeatingCurveChart({
    super.key,
    required this.parallelShift,
    required this.currentOutdoorTemp,
    required this.currentFlowTemp,
  });

  @override
  Widget build(BuildContext context) {
    // Generate curve data
    final activeCurve = HeatingAnalyticsService.generateHeatingCurve(
      parallelShift: parallelShift,
    );
    final idealCurve = HeatingAnalyticsService.generateHeatingCurve(
      parallelShift: 0,
    );

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minX: -20,
          maxX: 20,
          minY: 15,
          maxY: 85,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawHorizontalLine: true,
            drawVerticalLine: true,
            horizontalInterval: 10,
            verticalInterval: 10,
            getDrawingHorizontalLine: (_) => FlLine(
              color: const Color(0xFF3A3A44),
              strokeWidth: 0.5,
            ),
            getDrawingVerticalLine: (_) => FlLine(
              color: const Color(0xFF3A3A44),
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              axisNameWidget: const Text(
                'Vorlauf °C',
                style: TextStyle(
                  color: Color(0xFF9E9EA8),
                  fontSize: 10,
                ),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: 20,
                getTitlesWidget: (v, meta) => Text(
                  '${v.toInt()}',
                  style: const TextStyle(
                    color: Color(0xFF9E9EA8),
                    fontSize: 10,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: const Text(
                'Außentemperatur °C',
                style: TextStyle(
                  color: Color(0xFF9E9EA8),
                  fontSize: 10,
                ),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 10,
                getTitlesWidget: (v, meta) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${v.toInt()}',
                    style: const TextStyle(
                      color: Color(0xFF9E9EA8),
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: const Border(
              left: BorderSide(color: Color(0xFF3A3A44), width: 1),
              bottom: BorderSide(color: Color(0xFF3A3A44), width: 1),
            ),
          ),
          lineBarsData: [
            // Ideal curve (shift=0) — dashed reference line
            LineChartBarData(
              spots: idealCurve
                  .map((p) => FlSpot(p.outdoorTemp, p.flowTarget))
                  .toList(),
              isCurved: true,
              curveSmoothness: 0.3,
              color: const Color(0xFF66BB6A).withValues(alpha: 0.4),
              barWidth: 1.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              dashArray: [6, 4],
              belowBarData: BarAreaData(show: false),
            ),
            // Active curve (current shift) — solid accent line
            LineChartBarData(
              spots: activeCurve
                  .map((p) => FlSpot(p.outdoorTemp, p.flowTarget))
                  .toList(),
              isCurved: true,
              curveSmoothness: 0.3,
              gradient: const LinearGradient(
                colors: [Color(0xFFFF7043), Color(0xFFFFA726)],
              ),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFFFA726).withValues(alpha: 0.15),
                    const Color(0xFFFFA726).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
          // Operating point indicator
          extraLinesData: ExtraLinesData(
            verticalLines: [
              VerticalLine(
                x: currentOutdoorTemp.clamp(-20, 20),
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.5),
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
            ],
            horizontalLines: [
              HorizontalLine(
                y: currentFlowTemp.clamp(15, 85),
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.5),
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
            ],
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF35353F),
              getTooltipItems: (spots) => spots.map((spot) {
                return LineTooltipItem(
                  '${spot.x.toStringAsFixed(0)}°C → ${spot.y.toStringAsFixed(1)}°C',
                  const TextStyle(
                    color: Color(0xFFECECF0),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ),
    );
  }
}

/// A legend row for the heating curve chart.
class HeatingCurveLegend extends StatelessWidget {
  final double parallelShift;
  final double currentOutdoorTemp;
  final double currentFlowTemp;

  const HeatingCurveLegend({
    super.key,
    required this.parallelShift,
    required this.currentOutdoorTemp,
    required this.currentFlowTemp,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _LegendItem(
          color: const Color(0xFFFFA726),
          label: 'Deine Kurve (${parallelShift > 0 ? '+' : ''}${parallelShift.toStringAsFixed(0)})',
          dashed: false,
        ),
        const _LegendItem(
          color: Color(0xFF66BB6A),
          label: 'Ideal (Neutral)',
          dashed: true,
        ),
        _LegendItem(
          color: const Color(0xFF7C4DFF),
          label: 'Betriebspunkt '
              '(${currentOutdoorTemp.toStringAsFixed(0)}° / '
              '${currentFlowTemp.toStringAsFixed(0)}°)',
          dashed: true,
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.dashed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: dashed ? null : color,
            borderRadius: BorderRadius.circular(2),
            border: dashed ? Border.all(color: color, width: 1) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
