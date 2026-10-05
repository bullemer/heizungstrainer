/// Structured representation of a single Highcharts chart scraped from the
/// Brunata portal (one per consumption view), used by the detail drill-down.
library;

/// One data series within a [BrunataChart] (e.g. the current vs. the previous
/// billing period).
class BrunataChartSeries {
  /// Series label as shown by the portal, e.g. "Ausgewählter Abrechnungszeitraum".
  final String name;

  /// Numeric values, one per category/month.
  final List<double> values;

  /// Whether each value is an extrapolation (`isHochrechnung`). Same length as
  /// [values].
  final List<bool> extrapolated;

  const BrunataChartSeries({
    required this.name,
    required this.values,
    required this.extrapolated,
  });

  /// Sum of all values (actual + extrapolated).
  double get total => values.fold(0, (a, b) => a + b);

  /// Sum of the non-extrapolated (actually measured) values only.
  double get actualTotal {
    var sum = 0.0;
    for (var i = 0; i < values.length; i++) {
      if (i >= extrapolated.length || !extrapolated[i]) sum += values[i];
    }
    return sum;
  }

  bool isExtrapolatedAt(int i) => i < extrapolated.length && extrapolated[i];

  factory BrunataChartSeries.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as List?) ?? const [];
    final hr = (json['hr'] as List?) ?? const [];
    return BrunataChartSeries(
      name: (json['name'] ?? '').toString(),
      values: [
        for (final v in data) (v is num) ? v.toDouble() : 0.0,
      ],
      extrapolated: [
        for (var i = 0; i < data.length; i++)
          i < hr.length && (hr[i] == 1 || hr[i] == true),
      ],
    );
  }
}

/// A scraped chart with its series and axis metadata.
class BrunataChart {
  /// Which page this came from (`month_heizung`, `month_warmwasser`,
  /// `index`, `liegenschaft_heizung`, …).
  final String source;

  /// Chart title, e.g. "Monatsvergleich Heizung".
  final String title;

  /// Subtitle, e.g. "Ausgewählter Abrechnungszeitraum: 01.01.2026 - 31.12.2026".
  final String subtitle;

  /// Y-axis unit text, e.g. "Verbrauch in kWh" or "Verbrauch in kWh/m²".
  final String unit;

  /// Category labels (may be empty; for monthly charts these are synthesized).
  final List<String> categories;

  final List<BrunataChartSeries> series;

  const BrunataChart({
    required this.source,
    required this.title,
    required this.subtitle,
    required this.unit,
    required this.categories,
    required this.series,
  });

  /// True when the values are kWh (vs. e.g. kWh/m² for building comparison).
  bool get isKwh {
    final u = unit.toLowerCase();
    return u.contains('kwh') && !u.contains('m²') && !u.contains('m2');
  }

  /// Which series to compare against which (for the "Δ %" column and the
  /// building comparison): the user's / current series vs. the building
  /// average or the previous year. Null with fewer than two series.
  BrunataSeriesComparison? get comparison {
    if (series.length < 2) return null;
    const avgKeywords = ['durchschnitt', 'schnitt', 'mittel', 'gesamt', 'liegenschaft', 'gebäude', 'gebaeude', 'ø'];
    const userKeywords = ['wohnung', 'meine', 'mein ', 'nutzer', 'nutzungseinheit', 'kunde', 'ausgewählt', 'ausgewaehlt', 'ihr'];
    bool has(BrunataChartSeries s, List<String> keys) => keys.any((k) => s.name.toLowerCase().contains(k));

    // 1. Building average vs. own flat.
    BrunataChartSeries? avg;
    for (final s in series) {
      if (has(s, avgKeywords) && !has(s, userKeywords)) {
        avg = s;
        break;
      }
    }
    if (avg != null) {
      final own = series.firstWhere((s) => !identical(s, avg) && has(s, userKeywords),
          orElse: () => series.firstWhere((s) => !identical(s, avg)));
      return BrunataSeriesComparison(subject: own, reference: avg, kind: BrunataComparisonKind.buildingAverage);
    }

    // 2. Current period (has extrapolated months) vs. previous period.
    final years = {for (final s in series) s: int.tryParse(RegExp(r'(19|20)\d{2}').stringMatch(s.name) ?? '')};
    BrunataChartSeries? current;
    for (final s in series) {
      if (s.extrapolated.any((e) => e)) {
        current = s;
        break;
      }
    }
    current ??= () {
      final dated = series.where((s) => years[s] != null).toList()
        ..sort((a, b) => years[b]!.compareTo(years[a]!));
      return dated.isNotEmpty ? dated.first : null;
    }();
    if (current != null) {
      final others = series.where((s) => !identical(s, current)).toList();
      final cy = years[current];
      others.sort((a, b) {
        // closest earlier year first, else the first other series
        final ay = years[a], by = years[b];
        if (cy != null && ay != null && by != null) return (cy - ay).abs().compareTo((cy - by).abs());
        return 0;
      });
      return BrunataSeriesComparison(subject: current, reference: others.first, kind: BrunataComparisonKind.previousPeriod);
    }

    return BrunataSeriesComparison(subject: series[0], reference: series[1], kind: BrunataComparisonKind.other);
  }

  /// The portal's overview chart has cumulative columns ("bisher" and
  /// "Gesamtjahr"), which must not be added up.
  bool get isCumulativeOverview => source == 'index';

  /// Whether this chart concerns warm water (vs. heating).
  bool get isWarmWater {
    final t = title.toLowerCase();
    return t.contains('wasser') || t.contains('warmw');
  }

  Map<String, dynamic> toJson() => {
        'source': source,
        'title': title,
        'subtitle': subtitle,
        'unit': unit,
        'categories': categories,
        'series': [
          for (final s in series)
            {
              'name': s.name,
              'data': s.values,
              'hr': [for (final e in s.extrapolated) e ? 1 : 0],
            }
        ],
      };

  factory BrunataChart.fromJson(Map<String, dynamic> json) {
    return BrunataChart(
      source: (json['source'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      unit: (json['unit'] ?? '').toString(),
      categories: [
        for (final c in (json['categories'] as List?) ?? const [])
          c.toString(),
      ],
      series: [
        for (final s in (json['series'] as List?) ?? const [])
          BrunataChartSeries.fromJson((s as Map).cast<String, dynamic>()),
      ],
    );
  }
}


enum BrunataComparisonKind { buildingAverage, previousPeriod, other }

/// [subject] compared with [reference], month by month.
class BrunataSeriesComparison {
  final BrunataChartSeries subject;
  final BrunataChartSeries reference;
  final BrunataComparisonKind kind;

  const BrunataSeriesComparison({required this.subject, required this.reference, required this.kind});

  /// Short column header for the Δ % column.
  String get label => switch (kind) {
        BrunataComparisonKind.buildingAverage => 'Δ vs. Ø Haus',
        BrunataComparisonKind.previousPeriod => 'Δ vs. Vorjahr',
        BrunataComparisonKind.other => 'Δ %',
      };

  /// Percentage difference for row [i]; null if not comparable (missing,
  /// extrapolated or zero reference).
  double? percentAt(int i) {
    if (i >= subject.values.length || i >= reference.values.length) return null;
    if (subject.isExtrapolatedAt(i)) return null;
    final ref = reference.values[i];
    if (ref <= 0) return null;
    return (subject.values[i] - ref) / ref * 100;
  }

  /// Sum of [s] over the rows where the subject is measured – the same rows
  /// [totalPercent] compares, so the totals and the % always match.
  double comparableTotal(BrunataChartSeries s) {
    var sum = 0.0;
    for (var i = 0; i < s.values.length; i++) {
      if (i < subject.values.length && subject.isExtrapolatedAt(i)) continue;
      sum += s.values[i];
    }
    return sum;
  }

  /// Percentage over all rows where both are measured (same months only, so a
  /// part year is not compared with a full year).
  double? get totalPercent {
    var s = 0.0, r = 0.0;
    final n = subject.values.length < reference.values.length ? subject.values.length : reference.values.length;
    for (var i = 0; i < n; i++) {
      if (subject.isExtrapolatedAt(i)) continue;
      s += subject.values[i];
      r += reference.values[i];
    }
    return r > 0 ? (s - r) / r * 100 : null;
  }
}
