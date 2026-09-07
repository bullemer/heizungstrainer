import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/models/brunata_chart.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/settings_screen.dart';

/// Community & Liegenschafts-Vergleich Screen:
/// Displays building-wide and neighborhood efficiency comparisons,
/// weather-normalized heating metrics, and monthly consumption breakdowns.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  // ── Palette ──────────────────────────────────────────────────────────
  static const Color _background = Color(0xFF1E1E24);
  static const Color _card = Color(0xFF2A2A32);
  static const Color _border = Color(0xFF3A3A44);
  static const Color _accent = Color(0xFF7C4DFF);
  static const Color _accentLight = Color(0xFFB388FF);
  static const Color _textPrimary = Color(0xFFFFFFFF);
  static const Color _textSecondary = Color(0xFFB0B0BC);
  static const Color _green = Color(0xFF66BB6A);
  static const Color _orange = Color(0xFFFFA726);

  int _selectedFilterIndex = 0; // 0: Alle, 1: Liegenschaft, 2: Monate, 3: Warmwasser

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ECLProvider>();
    final data = provider.brunataData ?? BrunataMeterData.demo();
    final isSyncing = provider.isBrunataSyncing;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text(
          'Community Vergleich',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          if (isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _accentLight,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync_rounded, color: _accentLight),
              tooltip: 'Mit Brunata abgleichen',
              onPressed: () => provider.syncBrunataData(),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: _textSecondary),
            tooltip: 'Brunata Zugangsdaten & Tarif',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ── Sync Banner (if syncing or error) ─────────────────────────
          if (provider.brunataSyncError != null)
            _buildSyncErrorBanner(provider.brunataSyncError!),

          // ── Efficiency Headline Benchmark ─────────────────────────────
          _buildBenchmarkCard(data),
          const SizedBox(height: 14),

          // ── Weather-Adjustment / HGT Note ─────────────────────────────
          _buildWeatherNormalizationNote(),
          const SizedBox(height: 16),

          // ── Per-Medium YTD Summary ────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _MediumSummaryCard(
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
                child: _MediumSummaryCard(
                  icon: Icons.water_drop_rounded,
                  label: 'Warmwasser',
                  ytd: data.warmWaterYtdActual,
                  projection: data.warmWaterProjection,
                  price: data.pricePerKwh,
                  accent: const Color(0xFF42A5F5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Filter Chips ──────────────────────────────────────────────
          _buildFilterTabs(),
          const SizedBox(height: 16),

          // ── Filtered Charts ───────────────────────────────────────────
          ..._buildFilteredCharts(data),
        ],
      ),
    );
  }

  Widget _buildSyncErrorBanner(String error) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEF5350).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF5350), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Brunata Sync: $error (Demo-Daten aktiv)',
              style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenchmarkCard(BrunataMeterData data) {
    final diff = data.communityComparisonPercentage;
    final isBetter = diff <= 0;
    final badgeColor = isBetter ? _green : _orange;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Liegenschafts-Effizienz',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                ),
                child: Text(
                  isBetter ? 'Vorbildlich' : 'Optimierbar',
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                isBetter
                    ? '${diff.abs().toStringAsFixed(1)}%'
                    : '+${diff.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: badgeColor,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isBetter
                    ? 'unter dem Gebäude-Durchschnitt'
                    : 'über dem Gebäude-Durchschnitt',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isBetter
                ? 'Deine Wohnung verbraucht spürbar weniger Wärmeenergie als die 23 Vergleichswohnungen der Liegenschaft.'
                : 'Deine Wohnung liegt über dem Schnitt der 23 Vergleichswohnungen. Eine Absenkung der Heizkurve um 1–2 Stufen kann spürbar sparen.',
            style: const TextStyle(
              fontSize: 12.5,
              color: _textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherNormalizationNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.25)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.wb_sunny_outlined, size: 18, color: _accentLight),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Witterungsbereinigt nach VDI 3807 / HGT: Vergleiche mit Vorjahren und Nachbarn werden um die reale Kälteperiode bereinigt, um milde Winter fair gegenüberzustellen.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: _textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    final filters = ['Alle', 'Liegenschaft', 'Heizungsverlauf', 'Warmwasser'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < filters.length; i++) ...[
            ChoiceChip(
              label: Text(filters[i]),
              selected: _selectedFilterIndex == i,
              onSelected: (val) {
                if (val) setState(() => _selectedFilterIndex = i);
              },
              selectedColor: _accent.withValues(alpha: 0.25),
              backgroundColor: _card,
              labelStyle: TextStyle(
                color: _selectedFilterIndex == i ? _accentLight : _textSecondary,
                fontSize: 12.5,
                fontWeight: _selectedFilterIndex == i
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
              side: BorderSide(
                color: _selectedFilterIndex == i ? _accentLight : _border,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildFilteredCharts(BrunataMeterData data) {
    var charts = data.charts;
    if (_selectedFilterIndex == 1) {
      charts = charts.where((c) => c.source.contains('liegenschaft')).toList();
    } else if (_selectedFilterIndex == 2) {
      charts = charts.where((c) => c.source == 'month_heizung').toList();
    } else if (_selectedFilterIndex == 3) {
      charts = charts.where((c) => c.isWarmWater).toList();
    }

    if (charts.isEmpty) {
      return [
        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Text(
              'Keine Charts für diesen Filter vorhanden.',
              style: TextStyle(color: _textSecondary),
            ),
          ),
        ),
      ];
    }

    return [
      for (final c in charts) ...[
        _CommunityChartCard(chart: c, price: data.pricePerKwh),
        const SizedBox(height: 14),
      ],
    ];
  }
}

// ── Per-Medium Summary Card ────────────────────────────────────────────────
class _MediumSummaryCard extends StatelessWidget {
  const _MediumSummaryCard({
    required this.icon,
    required this.label,
    required this.ytd,
    required this.projection,
    required this.price,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final double ytd;
  final double projection;
  final double price;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  color: Color(0xFFFFFFFF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${_fmtKwh(ytd)} kWh',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFFFFF),
            ),
          ),
          Text(
            'bisher · ≈ ${_fmtEur(ytd * price)}',
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFFB0B0BC),
            ),
          ),
          if (projection > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Prognose ${_fmtKwh(projection)} kWh',
              style: TextStyle(
                fontSize: 12,
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '≈ ${_fmtEur(projection * price)}',
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFFB0B0BC),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Chart Breakdown Table Card ─────────────────────────────────────────────
class _CommunityChartCard extends StatelessWidget {
  const _CommunityChartCard({required this.chart, required this.price});

  final BrunataChart chart;
  final double price;

  static const _card = Color(0xFF2A2A32);
  static const _border = Color(0xFF3A3A44);
  static const _textPrimary = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFFB0B0BC);

  @override
  Widget build(BuildContext context) {
    final series = chart.series;
    final rows = chart.categories.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chart.title.isEmpty ? chart.source : chart.title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: _textPrimary,
            ),
          ),
          if (chart.subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              chart.subtitle,
              style: const TextStyle(fontSize: 11.5, color: _textSecondary),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Einheit: ${chart.unit}',
            style: TextStyle(
              fontSize: 11,
              color: _textSecondary.withValues(alpha: 0.8),
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
            cells: [for (final s in series) s.name],
            isHeader: true,
            colorFor: _seriesColor,
          ),
          const Divider(height: 14, color: _border),

          for (var r = 0; r < rows; r++)
            _TableRow(
              label: chart.categories[r],
              cells: [
                for (final s in series)
                  r < s.values.length ? _valueCell(s, r) : '–',
              ],
            ),

          const Divider(height: 16, color: _border),

          // Totals
          _TableRow(
            label: 'Summe (Ist)',
            cells: [for (final s in series) _fmtKwh(s.actualTotal)],
            isTotal: true,
          ),
          if (chart.isKwh)
            _TableRow(
              label: 'Kosten (ca.)',
              cells: [for (final s in series) _fmtEur(s.actualTotal * price)],
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
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: Color(0xFFB0B0BC)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    isHeader || isTotal ? FontWeight.bold : FontWeight.w500,
                color: isHeader
                    ? const Color(0xFFB0B0BC)
                    : (isTotal
                        ? const Color(0xFFFFFFFF)
                        : const Color(0xFFB0B0BC)),
              ),
            ),
          ),
          for (var i = 0; i < cells.length; i++)
            Expanded(
              child: Text(
                cells[i],
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight:
                      isHeader || isTotal ? FontWeight.bold : FontWeight.normal,
                  color: isHeader
                      ? (colorFor != null
                          ? colorFor!(i)
                          : const Color(0xFFB0B0BC))
                      : (isTotal
                          ? const Color(0xFFFFFFFF)
                          : const Color(0xFFFFFFFF)),
                ),
              ),
            ),
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
