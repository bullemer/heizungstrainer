import 'package:flutter/material.dart';

import 'package:heizungstrainer/models/brunata_chart.dart';

class _C {
  static const card = Color(0xFF2A2A32);
  static const border = Color(0xFF3A3A44);
  static const textPrimary = Color(0xFFECECF0);
  static const textMuted = Color(0xFF9E9EA8);
}

String _fmtKwh(double v) {
  if (v >= 100) return '${v.round()}';
  return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
}
String _fmtEur(double v) => '${v.toStringAsFixed(2)} €';

/// Brunata chart as a table: one column per series plus a Δ % column
/// (see [BrunataChart.comparison]).
class BrunataChartCard extends StatelessWidget {
  const BrunataChartCard({super.key, required this.chart, required this.price});

  final BrunataChart chart;
  final double price;

  @override
  Widget build(BuildContext context) {
    final series = chart.series;
    final rows = chart.categories.length;
    final cmp = chart.comparison;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chart.title.isEmpty ? chart.source : chart.title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: _C.textPrimary,
            ),
          ),
          if (chart.subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              chart.subtitle,
              style: const TextStyle(
                  fontSize: 11.5, color: _C.textMuted),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            chart.unit,
            style: TextStyle(
              fontSize: 11,
              color: _C.textMuted.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 12),

          // Legend
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (var i = 0; i < series.length; i++)
                _LegendDot(color: _seriesColor(i), label: series[i].name),
            ],
          ),
          const SizedBox(height: 10),

          // Header row
          _TableRow(
            label: '',
            cells: [for (final s in series) s.name, if (cmp != null) cmp.label],
            isHeader: true,
            colorFor: (i) => i < series.length ? _seriesColor(i) : _C.textMuted,
          ),
          const Divider(height: 14, color: _C.border),

          for (var r = 0; r < rows; r++)
            _TableRow(
              label: chart.categories[r],
              cells: [
                for (final s in series)
                  r < s.values.length
                      ? _valueCell(s, r)
                      : '–',
                if (cmp != null) _fmtPct(cmp.percentAt(r)),
              ],
              colorFor: cmp == null ? null : (i) => i == series.length ? _pctColor(cmp.percentAt(r)) : _C.textPrimary,
            ),

          const Divider(height: 16, color: _C.border),

          // Totals (actual measured). The overview chart's columns are
          // cumulative ("bisher" / "Gesamtjahr"), so adding them double-counts.
          if (!chart.isCumulativeOverview) _TableRow(
            label: cmp != null ? 'Summe (gleiche Monate)' : 'Summe (Ist)',
            cells: [
              for (final s in series) _fmtKwh(cmp != null ? cmp.comparableTotal(s) : s.actualTotal),
              if (cmp != null) _fmtPct(cmp.totalPercent),
            ],
            isTotal: true,
            colorFor: cmp == null ? null : (i) => i == series.length ? _pctColor(cmp.totalPercent) : _C.textPrimary,
          ),
          if (cmp != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${cmp.label}: „${cmp.subject.name}“ gegenüber „${cmp.reference.name}“. '
                '${chart.isCumulativeOverview ? 'Die Spalten sind kumuliert (bisher / Gesamtjahr) und werden nicht addiert' : 'Summe nur über die Monate, die in beiden Reihen gemessen sind'}; '
                '* = hochgerechnet (ohne %).',
                style: const TextStyle(fontSize: 10.5, color: _C.textMuted),
              ),
            ),
          if (chart.isKwh && !chart.isCumulativeOverview)
            _TableRow(
              label: 'Kosten (geschätzt)',
              cells: [
                for (final s in series) _fmtEur((cmp != null ? cmp.comparableTotal(s) : s.actualTotal) * price),
                if (cmp != null) '',
              ],
              isTotal: true,
            ),
        ],
      ),
    );
  }

  String _valueCell(BrunataChartSeries s, int r) {
    final v = _fmtKwh(s.values[r]);
    return s.isExtrapolatedAt(r) ? '$v*' : v;
  }

  static String _fmtPct(double? p) {
    if (p == null) return '–';
    final sign = p > 0.05 ? '+' : (p < -0.05 ? '−' : '±');
    return '$sign${p.abs().toStringAsFixed(0)} %';
  }

  /// Green = less than the reference (good), orange = more.
  static Color _pctColor(double? p) {
    if (p == null || p.abs() < 0.5) return _C.textMuted;
    return p < 0 ? const Color(0xFF66BB6A) : const Color(0xFFFF7043);
  }

  static Color _seriesColor(int i) {
    const palette = [
      Color(0xFFFFA726),
      Color(0xFF42A5F5),
      Color(0xFF66BB6A),
      Color(0xFFAB47BC),
    ];
    return palette[i % palette.length];
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11, color: _C.textMuted),
          ),
        ),
      ],
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.label,
    required this.cells,
    this.isHeader = false,
    this.isTotal = false,
    this.colorFor,
  });

  final String label;
  final List<String> cells;
  final bool isHeader;
  final bool isTotal;
  final Color Function(int)? colorFor;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: isHeader ? 10.5 : 12.5,
      fontWeight: isTotal || isHeader ? FontWeight.w700 : FontWeight.w400,
      color: isTotal
          ? _C.textPrimary
          : (isHeader
              ? _C.textMuted
              : _C.textPrimary),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(
                fontSize: isHeader ? 10.5 : 12,
                fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
                color: _C.textMuted,
              ),
            ),
          ),
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: 4,
              child: Text(
                cells[i],
                textAlign: TextAlign.right,
                maxLines: isHeader ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: colorFor != null
                    ? style.copyWith(color: colorFor!(i))
                    : style,
              ),
            ),
        ],
      ),
    );
  }
}
