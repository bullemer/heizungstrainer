import 'dart:convert';

/// One comfort period of the ECL weekly schedule. Times are HHMM as the
/// controller stores them (0, 30, 100, … 2330, 2400); start == stop (usually
/// 2400/2400) means the period is not used.
class SchedulePeriod {
  const SchedulePeriod(this.start, this.stop);

  static const unused = SchedulePeriod(2400, 2400);
  static const allDay = SchedulePeriod(0, 2400);

  final int start;
  final int stop;

  bool get isActive => start < stop;

  int get minutes => isActive ? _toMinutes(stop) - _toMinutes(start) : 0;

  static int _toMinutes(int hhmm) => (hhmm ~/ 100) * 60 + hhmm % 100;

  static String formatTime(int hhmm) =>
      '${(hhmm ~/ 100).toString().padLeft(2, '0')}:${(hhmm % 100).toString().padLeft(2, '0')}';

  @override
  String toString() => '${formatTime(start)}–${formatTime(stop)}';

  @override
  bool operator ==(Object other) => other is SchedulePeriod && other.start == start && other.stop == stop;

  @override
  int get hashCode => Object.hash(start, stop);
}

/// Weekly comfort schedule of an ECL heating circuit (Danfoss communication
/// description 6.7): 7 days × 3 periods. Outside the periods the controller
/// uses the saving ("Spar") room setpoint.
class WeekSchedule {
  WeekSchedule(List<List<SchedulePeriod>> days)
      : days = List.unmodifiable([for (final d in days) List<SchedulePeriod>.unmodifiable(d)]) {
    assert(days.length == 7 && days.every((d) => d.length == 3));
  }

  static const dayNames = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
  static const dayShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  /// Register address of a schedule value for circuit 1 (PNU 3110 + 10·day +
  /// 2·period [+1 for stop]; register = PNU − 1).
  static int address(int day, int period, {required bool stop, int basePnu = heatingBasePnu}) =>
      basePnu - 1 + 10 * day + 2 * period + (stop ? 1 : 0);

  /// Schedule areas (PNU of Monday P1 start), verified on A247.1:
  /// 3110 heating circuit, 3210 hot water, 3310 circulation pump P3.
  static const heatingBasePnu = 3110;
  static const dhwBasePnu = 3210;
  static const circulationBasePnu = 3310;

  /// From the 6 raw registers per day (P1 start, P1 stop, … P3 stop).
  factory WeekSchedule.fromRaw(List<List<int>> raw) => WeekSchedule([
        for (final d in raw) [for (var p = 0; p < 3; p++) SchedulePeriod(d[2 * p], d[2 * p + 1])],
      ]);

  final List<List<SchedulePeriod>> days;

  List<SchedulePeriod> activePeriods(int day) => days[day].where((p) => p.isActive).toList();

  bool hasComfort(int day) => activePeriods(day).isNotEmpty;

  String describeDay(int day) {
    final active = activePeriods(day);
    return active.isEmpty ? 'keine warme Zeit' : active.join(', ');
  }

  /// The day plan most days use (as a template for fixing a day), or null if
  /// no day has comfort periods.
  List<SchedulePeriod>? get mostCommonDay {
    final counts = <String, (int, List<SchedulePeriod>)>{};
    for (final d in days) {
      if (!d.any((p) => p.isActive)) continue;
      final key = d.join('|');
      counts[key] = ((counts[key]?.$1 ?? 0) + 1, d);
    }
    if (counts.isEmpty) return null;
    return counts.values.reduce((a, b) => b.$1 > a.$1 ? b : a).$2;
  }

  /// Hours per week outside comfort periods (= at the saving setpoint).
  double get loweredHoursPerWeek =>
      7 * 24 - days.expand((d) => d).fold<int>(0, (sum, p) => sum + p.minutes) / 60;

  /// Rough upper bound of the heating energy saved by lowering for
  /// [loweredHoursPerWeek] by [kelvin]: ~6 % per °C (as for the room
  /// setpoint), weighted by the share of the week. Upper bound because the
  /// house does not cool down to the saving setpoint at once.
  static double savingPercent({required double loweredHoursPerWeek, required double kelvin}) =>
      kelvin <= 0 ? 0 : 6.0 * kelvin * loweredHoursPerWeek / (7 * 24);

  bool sameAs(WeekSchedule other) => [for (var d = 0; d < 7; d++) sameDay(other, d)].every((same) => same);

  WeekSchedule withDay(int day, List<SchedulePeriod> periods) =>
      WeekSchedule([for (var d = 0; d < 7; d++) d == day ? periods : days[d]]);

  String encode() => jsonEncode([
        for (final d in days) [for (final p in d) [p.start, p.stop]],
      ]);

  static WeekSchedule? decode(String? raw) {
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List;
      return WeekSchedule([
        for (final d in list) [for (final p in d as List) SchedulePeriod((p as List)[0] as int, p[1] as int)],
      ]);
    } catch (_) {
      return null;
    }
  }

  bool sameDay(WeekSchedule other, int day) {
    for (var p = 0; p < 3; p++) {
      if (days[day][p] != other.days[day][p]) return false;
    }
    return true;
  }
}

/// Ready-made weekly plans for the heating schedule card.
class SchedulePreset {
  const SchedulePreset(this.id, this.title, this.description, this.weekday, this.weekend);

  final String id;
  final String title;
  final String description;
  final List<SchedulePeriod> weekday;
  final List<SchedulePeriod> weekend;

  static const _u = SchedulePeriod.unused;

  static const all = [
    SchedulePreset('always', 'Immer warm', 'rund um die Uhr warm, keine Absenkung',
        [SchedulePeriod.allDay, _u, _u], [SchedulePeriod.allDay, _u, _u]),
    SchedulePreset('night', 'Nachts absenken', 'warm 6–22 Uhr, nachts abgesenkt',
        [SchedulePeriod(600, 2200), _u, _u], [SchedulePeriod(600, 2200), _u, _u]),
    SchedulePreset('working', 'Berufstätig', 'Mo–Fr warm 6–8 und 16–22 Uhr, Wochenende 7–23 Uhr',
        [SchedulePeriod(600, 800), SchedulePeriod(1600, 2200), _u], [SchedulePeriod(700, 2300), _u, _u]),
  ];

  List<SchedulePeriod> periodsFor(int day) => day < 5 ? weekday : weekend;

  WeekSchedule get schedule => WeekSchedule([for (var d = 0; d < 7; d++) periodsFor(d)]);
}

/// Text for the ECL circuit mode (PNU 4201).
String eclModeLabel(double? code) => switch (code?.round()) {
      0 => 'Handbetrieb',
      1 => 'Zeitprogramm',
      2 => 'Dauernd Komfort',
      3 => 'Dauernd Spar',
      4 => 'Frostschutz',
      null => '–',
      final c => 'Code $c',
    };
