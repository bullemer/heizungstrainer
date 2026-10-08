import 'package:heizungstrainer/models/week_schedule.dart';

/// Suggested circulation pump times ("Optimale Zeiten"): the pump only runs
/// when hot water is typically drawn. Outside these times hot water is still
/// available – it just takes a little longer to reach the tap.
class CirculationProfile {
  const CirculationProfile({
    required this.id,
    required this.title,
    required this.description,
    required this.weekday,
    required this.weekend,
  });

  final String id;
  final String title;
  final String description;

  /// Periods (HHMM start/stop) for Mon–Fri and Sat/Sun.
  final List<SchedulePeriod> weekday;
  final List<SchedulePeriod> weekend;

  List<SchedulePeriod> periodsFor(int day) {
    final p = day < 5 ? weekday : weekend;
    return [...p, for (var i = p.length; i < 3; i++) SchedulePeriod.unused];
  }

  WeekSchedule get schedule => WeekSchedule([for (var d = 0; d < 7; d++) periodsFor(d)]);

  static const profiles = [
    CirculationProfile(
      id: 'working',
      title: 'Berufstätig',
      description: 'Werktags morgens und abends, am Wochenende tagsüber.',
      weekday: [SchedulePeriod(600, 830), SchedulePeriod(1700, 2200)],
      weekend: [SchedulePeriod(730, 2200)],
    ),
    CirculationProfile(
      id: 'home',
      title: 'Viel zu Hause',
      description: 'Homeoffice, Familie, Rente: tagsüber durchgehend, nachts aus.',
      weekday: [SchedulePeriod(600, 2200)],
      weekend: [SchedulePeriod(700, 2200)],
    ),
    CirculationProfile(
      id: 'minimal',
      title: 'Sparsam',
      description: 'Nur zu den Hauptzeiten morgens und abends – sonst kurz warten.',
      weekday: [SchedulePeriod(600, 800), SchedulePeriod(1800, 2100)],
      weekend: [SchedulePeriod(730, 1000), SchedulePeriod(1800, 2100)],
    ),
  ];
}

/// Average pump hours per day of [schedule].
double circulationHoursPerDay(WeekSchedule schedule) {
  var minutes = 0;
  for (var d = 0; d < 7; d++) {
    for (final p in schedule.activePeriods(d)) {
      minutes += p.minutes;
    }
  }
  return minutes / 7 / 60;
}

/// Estimated yearly heat saving of running the circulation [hoursSavedPerDay]
/// fewer hours: an insulated loop loses roughly 100–200 W while running
/// (about 20 m at 5–10 W/m). Returns (low, high) kWh per year.
({double low, double high}) circulationSavingKwh(double hoursSavedPerDay) {
  final h = hoursSavedPerDay < 0 ? 0.0 : hoursSavedPerDay;
  return (low: h * 0.1 * 365, high: h * 0.2 * 365);
}
