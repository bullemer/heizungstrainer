/// Data model for Brunata cost portal integration.
///
/// Represents metered heating cost and consumption data from the
/// Brunata billing portal, used for cost visualization and
/// community efficiency comparisons.
library;

import 'package:heizungstrainer/models/brunata_chart.dart';

/// A snapshot of the user's current billing period data from
/// the Brunata metering portal.
class BrunataMeterData {
  /// Current billing period heating cost in Euros (estimated from [pricePerKwh]).
  final double currentBillingPeriodCost;

  /// Total consumed kilowatt-hours in the current period (YTD actual heating).
  final double consumedKwh;

  /// Percentage comparison against the anonymized community average.
  /// Positive = above average (worse), negative = below average (better).
  /// Example: +15.0 means 15% above the community average.
  final double communityComparisonPercentage;

  /// Billing period start date.
  final DateTime periodStart;

  /// Billing period end date.
  final DateTime periodEnd;

  /// Price per kWh used to estimate all costs.
  final double pricePerKwh;

  /// Year-to-date actual / full-year projection per medium (kWh).
  final double heatingYtdActual;
  final double heatingProjection;
  final double warmWaterYtdActual;
  final double warmWaterProjection;

  /// All scraped charts (monthly Heizung/Warmwasser, YTD overview, building
  /// comparison), preserved for the detail drill-down.
  final List<BrunataChart> charts;

  const BrunataMeterData({
    required this.currentBillingPeriodCost,
    required this.consumedKwh,
    required this.communityComparisonPercentage,
    required this.periodStart,
    required this.periodEnd,
    this.pricePerKwh = 0.10,
    this.heatingYtdActual = 0,
    this.heatingProjection = 0,
    this.warmWaterYtdActual = 0,
    this.warmWaterProjection = 0,
    this.charts = const [],
  });

  /// Whether the user's consumption is above the community average.
  bool get isAboveCommunityAverage => communityComparisonPercentage > 0;

  /// Cost per kWh in the current period.
  double get costPerKwh =>
      consumedKwh > 0 ? currentBillingPeriodCost / consumedKwh : 0;

  /// Whether detailed chart data is available for the drill-down view.
  bool get hasDetail => charts.isNotEmpty;

  /// Returns a copy with cost fields recomputed for a new tariff.
  BrunataMeterData copyWithPrice(double newPrice) {
    return BrunataMeterData(
      currentBillingPeriodCost: consumedKwh * newPrice,
      consumedKwh: consumedKwh,
      communityComparisonPercentage: communityComparisonPercentage,
      periodStart: periodStart,
      periodEnd: periodEnd,
      pricePerKwh: newPrice,
      heatingYtdActual: heatingYtdActual,
      heatingProjection: heatingProjection,
      warmWaterYtdActual: warmWaterYtdActual,
      warmWaterProjection: warmWaterProjection,
      charts: charts,
    );
  }

  Map<String, dynamic> toJson() => {
        'currentBillingPeriodCost': currentBillingPeriodCost,
        'consumedKwh': consumedKwh,
        'communityComparisonPercentage': communityComparisonPercentage,
        'periodStart': periodStart.toIso8601String(),
        'periodEnd': periodEnd.toIso8601String(),
        'pricePerKwh': pricePerKwh,
        'heatingYtdActual': heatingYtdActual,
        'heatingProjection': heatingProjection,
        'warmWaterYtdActual': warmWaterYtdActual,
        'warmWaterProjection': warmWaterProjection,
        'charts': [for (final c in charts) c.toJson()],
      };

  factory BrunataMeterData.fromJson(Map<String, dynamic> json) {
    return BrunataMeterData(
      currentBillingPeriodCost:
          (json['currentBillingPeriodCost'] as num).toDouble(),
      consumedKwh: (json['consumedKwh'] as num).toDouble(),
      communityComparisonPercentage:
          (json['communityComparisonPercentage'] as num).toDouble(),
      periodStart: DateTime.parse(json['periodStart'] as String),
      periodEnd: DateTime.parse(json['periodEnd'] as String),
      pricePerKwh: (json['pricePerKwh'] as num?)?.toDouble() ?? 0.10,
      heatingYtdActual:
          (json['heatingYtdActual'] as num?)?.toDouble() ?? 0.0,
      heatingProjection:
          (json['heatingProjection'] as num?)?.toDouble() ?? 0.0,
      warmWaterYtdActual:
          (json['warmWaterYtdActual'] as num?)?.toDouble() ?? 0.0,
      warmWaterProjection:
          (json['warmWaterProjection'] as num?)?.toDouble() ?? 0.0,
      charts: [
        for (final c in (json['charts'] as List?) ?? const [])
          BrunataChart.fromJson((c as Map).cast<String, dynamic>()),
      ],
    );
  }

  /// Create demo/placeholder data for UI development.
  /// Will be replaced with actual Brunata API integration.
  factory BrunataMeterData.demo() {
    final now = DateTime.now();
    const categories = [
      'Jan',
      'Feb',
      'Mär',
      'Apr',
      'Mai',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Okt',
      'Nov',
      'Dez'
    ];

    return BrunataMeterData(
      currentBillingPeriodCost: 187.50,
      consumedKwh: 1450,
      communityComparisonPercentage: -14.2,
      periodStart: DateTime(now.year, 1, 1),
      periodEnd: DateTime(now.year, 12, 31),
      pricePerKwh: 0.12,
      heatingYtdActual: 1450,
      heatingProjection: 2850,
      warmWaterYtdActual: 420,
      warmWaterProjection: 840,
      charts: [
        const BrunataChart(
          source: 'liegenschaft_heizung',
          title: 'Liegenschafts-Vergleich Heizung',
          subtitle: 'Verbrauch im Vergleich zu 23 Wohneinheiten',
          unit: 'kWh/m²',
          categories: categories,
          series: [
            BrunataChartSeries(
              name: 'Meine Wohnung',
              values: [
                14.2, 12.8, 9.5, 5.1, 2.0, 0.0, 0.0, 0.0, 1.8, 6.2, 11.0, 13.5
              ],
              extrapolated: [
                false, false, false, false, false, false, false, false, false, false, false, false
              ],
            ),
            BrunataChartSeries(
              name: 'Liegenschafts-Schnitt',
              values: [
                18.5, 16.2, 12.0, 6.8, 2.5, 0.0, 0.0, 0.0, 2.4, 8.1, 14.2, 17.0
              ],
              extrapolated: [
                false, false, false, false, false, false, false, false, false, false, false, false
              ],
            ),
          ],
        ),
        const BrunataChart(
          source: 'month_heizung',
          title: 'Monatsvergleich Heizung',
          subtitle: 'Aktuelle Periode vs. Vorjahr',
          unit: 'kWh',
          categories: categories,
          series: [
            BrunataChartSeries(
              name: '2025/2026',
              values: [
                260, 220, 180, 95, 30, 0, 0, 0, 25, 110, 210, 250
              ],
              extrapolated: [
                false, false, false, false, false, false, false, false, true, true, true, true
              ],
            ),
            BrunataChartSeries(
              name: '2024/2025',
              values: [
                290, 250, 205, 110, 40, 0, 0, 0, 35, 125, 230, 280
              ],
              extrapolated: [
                false, false, false, false, false, false, false, false, false, false, false, false
              ],
            ),
          ],
        ),
        const BrunataChart(
          source: 'liegenschaft_warmwasser',
          title: 'Liegenschafts-Vergleich Warmwasser',
          subtitle: 'Verbrauch im Vergleich zum Gebäude-Mittel',
          unit: 'kWh',
          categories: categories,
          series: [
            BrunataChartSeries(
              name: 'Meine Wohnung',
              values: [
                42, 38, 40, 39, 37, 35, 33, 34, 36, 38, 40, 41
              ],
              extrapolated: [
                false, false, false, false, false, false, false, false, false, false, false, false
              ],
            ),
            BrunataChartSeries(
              name: 'Liegenschafts-Schnitt',
              values: [
                48, 45, 46, 44, 42, 40, 38, 39, 41, 43, 46, 47
              ],
              extrapolated: [
                false, false, false, false, false, false, false, false, false, false, false, false
              ],
            ),
          ],
        ),
      ],
    );
  }
}
