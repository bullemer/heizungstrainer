/// A holiday period stored in the heating controller itself, so the
/// controller runs it without the app (e.g. Danfoss ECL holiday programs).
///
/// Danfoss ECL (communication description 6.9, operating guide A247 6.3):
/// 7 registers per schedule from PNU 10700 (register 10699): mode, start
/// day/month/year, end day/month/year. The period runs from the start date
/// 00:00 to the end date 00:00; the end must be at least one day after the
/// start; year ≤ 2050. Modes: 0 off (scheduled operation), 1 comfort,
/// 2 comfort 7–23 h, 3 saving, 4 frost protection.
library;

enum ControllerHolidayMode {
  off(0, 'aus'),
  comfort(1, 'Komfort'),
  comfort7to23(2, 'Komfort 7–23 Uhr'),
  saving(3, 'Spar'),
  frost(4, 'Frostschutz');

  const ControllerHolidayMode(this.code, this.label);
  final int code;
  final String label;

  static ControllerHolidayMode fromCode(int code) =>
      values.firstWhere((m) => m.code == code, orElse: () => ControllerHolidayMode.off);
}

class ControllerHolidayEntry {
  const ControllerHolidayEntry({required this.slot, required this.mode, required this.start, required this.end});

  /// Schedule number 1–12 (P1–P12 in the controller).
  final int slot;
  final ControllerHolidayMode mode;

  /// Dates only (00:00); null if the stored date is invalid.
  final DateTime? start;
  final DateTime? end;

  bool get isSet => mode != ControllerHolidayMode.off;

  /// Set and not over yet at [now].
  bool isPendingOrRunning(DateTime now) => isSet && end != null && end!.isAfter(now);

  bool isRunning(DateTime now) =>
      isPendingOrRunning(now) && start != null && !start!.isAfter(now);

  /// Register address of value [index] (0 = mode … 6 = end year) of [slot].
  static int address(int slot, int index) => 10699 + 7 * (slot - 1) + index;

  /// From the 7 raw registers of one schedule.
  static ControllerHolidayEntry fromRaw(int slot, List<int> raw) {
    DateTime? date(int d, int m, int y) {
      if (y < 2000 || m < 1 || m > 12 || d < 1 || d > 31) return null;
      final dt = DateTime(y, m, d);
      return dt.month == m ? dt : null;
    }

    return ControllerHolidayEntry(
      slot: slot,
      mode: ControllerHolidayMode.fromCode(raw[0]),
      start: date(raw[1], raw[2], raw[3]),
      end: date(raw[4], raw[5], raw[6]),
    );
  }

  static String fmtDate(DateTime? d) => d == null
      ? '?'
      : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String describe() => isSet ? 'P$slot ${mode.label} ${fmtDate(start)} 00:00 – ${fmtDate(end)} 00:00' : 'P$slot aus';
}

/// Which of the controller's holiday schedules belong to the heating circuit,
/// per application (the 12 schedules are shared between common/heating/DHW).
abstract final class ControllerHolidayLayout {
  /// Null = not verified for this application → the app keeps its own
  /// holiday mode instead of writing to the controller.
  static List<int>? heatingSlotsFor(String? application) {
    if (application == null) return null;
    if (application.startsWith('A247')) return a247HeatingSlots;
    return null;
  }

  /// A247.1: heating-circuit holiday schedules. Null until verified live
  /// (set one heating holiday in the Danfoss app/portal and see which
  /// schedule changes) – never write to an unverified slot.
  static const List<int>? a247HeatingSlots = null;

  /// Controller dates for an absence: start = start day 00:00; end = the
  /// midnight at or before [heatUpFrom] (when normal heating must resume so
  /// the home is warm on return – never later). Null if shorter than a day.
  static ({DateTime start, DateTime end})? datesFor({required DateTime start, required DateTime heatUpFrom}) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(heatUpFrom.year, heatUpFrom.month, heatUpFrom.day);
    if (e.difference(s).inHours < 24) return null;
    if (e.year > 2050) return null;
    return (start: s, end: e);
  }
}
