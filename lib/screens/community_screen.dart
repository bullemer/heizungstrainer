import 'package:flutter/material.dart';
import 'package:heizungstrainer/widgets/brunata_chart_card.dart';
import 'package:provider/provider.dart';

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
    final data = provider.brunataData;
    final isSyncing = provider.isBrunataSyncing;
    final billingName = provider.currentBillingDescriptor.name;

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
              tooltip: 'Mit $billingName abgleichen',
              onPressed: () => provider.syncBrunataData(),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: _textSecondary),
            tooltip: '$billingName Zugangsdaten & Tarif',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: data == null
          ? _buildUnsyncedEmptyState(context, provider)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // ── Sync Banner (if syncing or error) ─────────────────────────
                if (provider.brunataSyncError != null)
                  _buildSyncErrorBanner(provider.brunataSyncError!, billingName),

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
                        isMetered: data.hasWarmWater,
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

  Widget _buildUnsyncedEmptyState(BuildContext context, ECLProvider provider) {
    final billingName = provider.currentBillingDescriptor.name;
    final isSyncing = provider.isBrunataSyncing;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (provider.brunataSyncError != null) ...[
              _buildSyncErrorBanner(provider.brunataSyncError!, billingName),
              const SizedBox(height: 16),
            ],
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_sync_outlined,
                size: 36,
                color: _accentLight,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Noch keine Abrechnungsdaten',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Synchronisiere die Verbrauchsdaten mit $billingName, um den Liegenschafts-Vergleich, Vorjahreswerte und Monatsanalysen anzuzeigen.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isSyncing ? null : () => provider.syncBrunataData(),
                icon: isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(
                    isSyncing ? 'Synchronisiere…' : 'Jetzt mit $billingName abgleichen'),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              icon: const Icon(Icons.key_rounded, size: 18),
              label: const Text('Zugangsdaten prüfen / anpassen'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _textSecondary,
                side: const BorderSide(color: _border),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncErrorBanner(String error, String providerName) {
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
              '$providerName Sync: $error',
              style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenchmarkCard(BrunataMeterData data) {
    final diff = data.communityComparisonPercentage;
    final isNeutral = diff.abs() < 0.05;
    final isBetter = diff < 0;
    final badgeColor = isNeutral
        ? const Color(0xFF64B5F6)
        : (isBetter ? _green : _orange);

    final badgeText = isNeutral
        ? 'Im Schnitt'
        : (isBetter ? 'Vorbildlich' : 'Optimierbar');

    final diffText = isNeutral
        ? '0.0%'
        : (isBetter
            ? '${diff.abs().toStringAsFixed(1)}%'
            : '+${diff.toStringAsFixed(1)}%');

    final comparisonText = isNeutral
        ? 'im Liegenschafts-Durchschnitt'
        : (isBetter
            ? 'unter dem Gebäude-Durchschnitt'
            : 'über dem Gebäude-Durchschnitt');

    final explanationText = isNeutral
        ? 'Deine Wohnung liegt genau im Durchschnitt der Liegenschaft.'
        : (isBetter
            ? 'Deine Wohnung verbraucht je m² ${diff.abs().toStringAsFixed(1)} % weniger Wärmeenergie als der Liegenschafts-Durchschnitt (gemessene Monate des laufenden Zeitraums).'
            : 'Deine Wohnung liegt je m² ${diff.toStringAsFixed(1)} % über dem Schnitt der Liegenschaft (gemessene Monate des laufenden Zeitraums).');

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
                  badgeText,
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
                diffText,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: badgeColor,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                comparisonText,
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
            explanationText,
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
      if (_selectedFilterIndex == 3 && !data.hasWarmWater) {
        return [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF42A5F5).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.water_drop_outlined,
                    size: 32,
                    color: Color(0xFF42A5F5),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Keine Warmwasserdaten erfasst',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Im Brunata-Portal sind für diese Wohneinheit keine separaten Warmwasserzähler registriert. '
                  'Die Warmwasseraufbereitung erfolgt in dieser Liegenschaft in der Regel dezentral (z. B. elektrischer Durchlauferhitzer) '
                  'oder wird ohne getrennte Zähler abgerechnet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: _textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ];
      }
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
        BrunataChartCard(chart: c, price: data.pricePerKwh),
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
        color: const Color(0xFF2A2A32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  color: isMetered ? accent : const Color(0xFF8E8E9A), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: Color(0xFFFFFFFF),
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
                      color: Color(0xFFB0B0BC),
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
          ] else ...[
            const Text(
              'Nicht erfasst',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFFB0B0BC),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Kein Zähler im Portal',
              style: TextStyle(
                fontSize: 11.5,
                color: Color(0xFF8E8E9A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Nur Heizung wird über Brunata abgerechnet.',
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

// ── Chart Breakdown Table Card ─────────────────────────────────────────────

String _fmtKwh(double v) {
  if (v >= 100) return '${v.round()}';
  return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
}

String _fmtEur(double v) => '${v.toStringAsFixed(2)} €';
