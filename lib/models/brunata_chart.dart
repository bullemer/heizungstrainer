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
