import 'package:flutter/material.dart';

import 'package:heizungstrainer/models/brunata_chart.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';

/// Detailed drill-down of all Brunata measurements and estimated costs:
/// per-medium year-to-date / projection summary plus every scraped chart
/// (monthly Heizung, monthly Warmwasser, overview, building comparison).
class BrunataDetailScreen extends StatelessWidget {
  const BrunataDetailScreen({super.key, required this.data});

  final BrunataMeterData data;

  static const _bg = Color(0xFF1E1E24);
  static const _card = Color(0xFF2A2A32);
  static const _border = Color(0xFF3A3A44);
  static const _accent = Color(0xFFFFA726);
  static const _textPrimary = Color(0xFFECECF0);
  static const _textMuted = Color(0xFF9E9EA8);

  @override
  Widget build(BuildContext context) {
    // Keep a stable, meaningful order: overview, monthly, building comparison.
    const order = [
      'index',
      'month_heizung',
      'month_warmwasser',
      'liegenschaft_heizung',
      'liegenschaft_warmwasser',
    ];
    final charts = [...data.charts]..sort((a, b) {
        final ia = order.indexOf(a.source);
        final ib = order.indexOf(b.source);
        return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
      });

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          'Brunata Details',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _TariffNote(price: data.pricePerKwh),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  icon: Icons.local_fire_department_rounded,
                  label: 'Heizung',
                  ytd: data.heatingYtdActual,
                  projection: data.heatingProjection,
                  price: data.pricePerKwh,
                  accent: const Color(0xFFFF7043),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  icon: Icons.water_drop_rounded,
                  label: 'Warmwasser',
                  ytd: data.warmWaterYtdActual,
                  projection: data.warmWaterProjection,
                  price: data.pricePerKwh,
                  accent: const Color(0xFF42A5F5),
                  isMetered: data.hasWarmWater,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (charts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'Keine Detaildaten verfügbar.\nBitte zuerst synchronisieren.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textMuted),
                ),
              ),
            )
          else
            for (final c in charts) ...[
              _ChartCard(chart: c, price: data.pricePerKwh),
              const SizedBox(height: 14),
            ],
        ],
      ),
    );
  }
}

String _fmtKwh(double v) {
  if (v >= 100) return '${v.round()}';
  return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
}

String _fmtEur(double v) => '${v.toStringAsFixed(2)} €';

// ── tariff banner ─────────────────────────────────────────────────────────
class _TariffNote extends StatelessWidget {
  const _TariffNote({required this.price});
  final double price;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: BrunataDetailScreen._accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: BrunataDetailScreen._accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: BrunataDetailScreen._accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Kosten sind Schätzungen auf Basis von '
              '${price.toStringAsFixed(2).replaceAll('.', ',')} €/kWh. '
              'Das Portal liefert nur kWh.',
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: BrunataDetailScreen._textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── per-medium summary card ───────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.ytd,
    required this.projection,
    required this.price,
    required this.accent,
    this.isMetered = true,
  });

  final IconData icon;
  final String label;
  final double ytd;
  final double projection;
  final double price;
  final Color accent;
  final bool isMetered;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BrunataDetailScreen._card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BrunataDetailScreen._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  color: isMetered ? accent : BrunataDetailScreen._textMuted,
                  size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: BrunataDetailScreen._textPrimary,
                  ),
                ),
              ),
              if (!isMetered)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Dezentral',
                    style: TextStyle(
                      fontSize: 10,
                      color: BrunataDetailScreen._textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (isMetered) ...[
            Text(
              '${_fmtKwh(ytd)} kWh',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: BrunataDetailScreen._textPrimary,
              ),
            ),
            Text(
              'bisher · ≈ ${_fmtEur(ytd * price)}',
              style: const TextStyle(
                  fontSize: 11.5, color: BrunataDetailScreen._textMuted),
            ),
            if (projection > 0) ...[
              const SizedBox(height: 10),
              Text(
                'Hochrechnung ${_fmtKwh(projection)} kWh',
                style: TextStyle(
                  fontSize: 12,
                  color: accent.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '≈ ${_fmtEur(projection * price)}',
                style: const TextStyle(
                    fontSize: 11.5, color: BrunataDetailScreen._textMuted),
              ),
            ],
          ] else ...[
            const Text(
              'Nicht erfasst',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: BrunataDetailScreen._textMuted,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Kein Zähler im Portal',
              style: TextStyle(
                fontSize: 11.5,
                color: BrunataDetailScreen._textMuted,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Nur Heizung wird über das Portal erfasst.',
              style: TextStyle(
                fontSize: 10.5,
                color: Color(0xFF70707D),
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── one scraped chart rendered as a breakdown table ───────────────────────
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.chart, required this.price});

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
        color: BrunataDetailScreen._card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BrunataDetailScreen._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chart.title.isEmpty ? chart.source : chart.title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: BrunataDetailScreen._textPrimary,
            ),
          ),
          if (chart.subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              chart.subtitle,
              style: const TextStyle(
                  fontSize: 11.5, color: BrunataDetailScreen._textMuted),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            chart.unit,
            style: TextStyle(
              fontSize: 11,
              color: BrunataDetailScreen._textMuted.withValues(alpha: 0.8),
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
            colorFor: (i) => i < series.length ? _seriesColor(i) : BrunataDetailScreen._textMuted,
          ),
          const Divider(height: 14, color: BrunataDetailScreen._border),

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
              colorFor: cmp == null ? null : (i) => i == series.length ? _pctColor(cmp.percentAt(r)) : BrunataDetailScreen._textPrimary,
            ),

          const Divider(height: 16, color: BrunataDetailScreen._border),

          // Totals (actual measured)
          _TableRow(
            label: 'Summe (Ist)',
            cells: [for (final s in series) _fmtKwh(s.actualTotal), if (cmp != null) _fmtPct(cmp.totalPercent)],
            isTotal: true,
            colorFor: cmp == null ? null : (i) => i == series.length ? _pctColor(cmp.totalPercent) : BrunataDetailScreen._textPrimary,
          ),
          if (cmp != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${cmp.label}: „${cmp.subject.name}“ gegenüber „${cmp.reference.name}“. '
                'Summe nur über gemessene Monate; * = hochgerechnet (ohne %).',
                style: const TextStyle(fontSize: 10.5, color: BrunataDetailScreen._textMuted),
              ),
            ),
          if (chart.isKwh)
            _TableRow(
              label: 'Kosten (geschätzt)',
              cells: [for (final s in series) _fmtEur(s.actualTotal * price), if (cmp != null) ''],
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
    if (p == null || p.abs() < 0.5) return BrunataDetailScreen._textMuted;
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
                fontSize: 11, color: BrunataDetailScreen._textMuted),
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
          ? BrunataDetailScreen._textPrimary
          : (isHeader
              ? BrunataDetailScreen._textMuted
              : BrunataDetailScreen._textPrimary),
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
                color: BrunataDetailScreen._textMuted,
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
