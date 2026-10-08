import 'package:heizungstrainer/models/controller_holiday.dart';
import 'package:heizungstrainer/models/week_schedule.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';
import 'package:heizungstrainer/utils/number_format.dart';

/// "Einstellungs-Check": rules that look at the controller's real settings
/// and explain misconfigurations in plain words, with a way to fix them.
/// Pure logic – the provider assembles [ConfigCheckInput] from its readings.

enum FindingSeverity { problem, warning, hint }

enum FindingArea { heating, hotWater, controller }

/// Where the user can fix a finding.
enum FindingAction {
  fixSavingSetpoint,
  fixScheduleDays,
  setMaxFlow,
  openCurveAssistant,
  pickBuildingProfile,
  openHotWater,
  openLiveView,
  none,
}

class ConfigFinding {
  const ConfigFinding({
    required this.id,
    required this.area,
    required this.severity,
    required this.title,
    required this.detail,
    this.action = FindingAction.none,
  });

  /// Stable id (used to hide "ist so gewollt" findings).
  final String id;
  final FindingArea area;
  final FindingSeverity severity;
  final String title;
  final String detail;
  final FindingAction action;
}

class ConfigCheckInput {
  const ConfigCheckInput({
    this.comfort,
    this.saving,
    this.heatingMode,
    this.schedule,
    this.curve,
    this.reference,
    this.summerCutoff,
    this.maxFlow,
    this.dhwMode,
    this.dhwComfort,
    this.dhwSaving,
    this.antiBacteriaTemp,
    this.antiBacteriaDays,
    this.circulation,
    this.alarms = const {},
    this.clockOffset,
    this.heatingHolidays = const [],
    this.now,
  });

  final double? comfort;
  final double? saving;
  final int? heatingMode;
  final WeekSchedule? schedule;
  final ControllerHeatingCurve? curve;
  final BuildingReference? reference;
  final double? summerCutoff;
  final double? maxFlow;
  final int? dhwMode;
  final double? dhwComfort;
  final double? dhwSaving;
  final int? antiBacteriaTemp;
  final int? antiBacteriaDays;
  final WeekSchedule? circulation;
  final Set<int> alarms;

  /// Controller clock minus phone clock.
  final Duration? clockOffset;
  final List<ControllerHolidayEntry> heatingHolidays;
  final DateTime? now;
}

/// About 6 % heating energy per 1 K room temperature (co2online rule of thumb).
const double _percentPerKelvin = 6;

List<ConfigFinding> runConfigCheck(ConfigCheckInput i) {
  final out = <ConfigFinding>[];
  String t(double v) => '${v.fixed(v == v.roundToDouble() ? 0 : 1)} °C';

  // ── Controller ─────────────────────────────────────────────────────
  for (final n in i.alarms.toList()..sort()) {
    out.add(ConfigFinding(
      id: 'alarm_$n',
      area: FindingArea.controller,
      severity: FindingSeverity.problem,
      title: 'Regler meldet Alarm $n',
      detail: 'Der Regler hat eine Störung erkannt. Details am Regler unter „Alarm“ oder in der Anleitung '
          'der Danfoss-Applikation.',
      action: FindingAction.openLiveView,
    ));
  }
  final offset = i.clockOffset;
  if (offset != null && offset.abs() > const Duration(minutes: 10)) {
    final min = offset.inMinutes;
    out.add(ConfigFinding(
      id: 'clock',
      area: FindingArea.controller,
      severity: FindingSeverity.warning,
      title: 'Uhr des Reglers geht ${min.abs()} min ${min > 0 ? 'vor' : 'nach'}',
      detail: 'Zeitprogramme, Zirkulation und Urlaub laufen nach der Regler-Uhr – sie schalten '
          'entsprechend zu früh oder zu spät. Uhrzeit am Regler korrigieren.',
    ));
  }
  final now = i.now ?? DateTime.now();
  for (final h in i.heatingHolidays) {
    if (h.isSet && h.end != null && !h.end!.isAfter(now)) {
      out.add(ConfigFinding(
        id: 'holiday_old_${h.slot}',
        area: FindingArea.controller,
        severity: FindingSeverity.hint,
        title: 'Abgelaufener Urlaub im Regler (P${h.slot})',
        detail: '${h.describe()} ist vorbei, aber noch eingetragen. Er stört nicht, belegt aber einen der '
            '4 Urlaubsplätze des Heizkreises.',
      ));
    }
  }

  // ── Heating ────────────────────────────────────────────────────────
  final comfort = i.comfort, saving = i.saving;
  if (i.heatingMode != null && i.heatingMode != 1 && i.heatingMode != 2) {
    out.add(ConfigFinding(
      id: 'heating_mode',
      area: FindingArea.heating,
      severity: i.heatingMode == 0 ? FindingSeverity.problem : FindingSeverity.warning,
      title: switch (i.heatingMode) {
        0 => 'Heizkreis steht auf Handbetrieb',
        3 => 'Heizkreis dauerhaft auf Spar',
        4 => 'Heizkreis auf Frostschutz',
        _ => 'Ungewöhnliche Betriebsart des Heizkreises',
      },
      detail: 'Der Regler folgt weder Zeitprogramm noch Komfort-Sollwert. Wenn das nicht gewollt ist, '
          'am Regler auf „Zeitprogramm“ stellen.',
    ));
  }
  if (comfort != null && saving != null && saving > comfort) {
    out.add(ConfigFinding(
      id: 'saving_above_comfort',
      area: FindingArea.heating,
      severity: FindingSeverity.problem,
      title: 'Spar-Sollwert höher als Komfort',
      detail: 'Spar ${t(saving)}, Komfort ${t(comfort)}: außerhalb der Komfortzeiten heizt der Regler wärmer '
          'statt sparsamer, und ein Urlaub im Regler würde nicht absenken. Üblich sind 2–4 °C unter Komfort.',
      action: FindingAction.fixSavingSetpoint,
    ));
  }
  final schedule = i.schedule;
  if (schedule != null && (i.heatingMode == null || i.heatingMode == 1)) {
    final empty = [for (var d = 0; d < 7; d++) if (!schedule.hasComfort(d)) d];
    if (empty.isNotEmpty && empty.length < 7) {
      final warmer = comfort != null && saving != null && saving > comfort;
      out.add(ConfigFinding(
        id: 'schedule_empty_days',
        area: FindingArea.heating,
        severity: warmer ? FindingSeverity.problem : FindingSeverity.hint,
        title: '${empty.map((d) => WeekSchedule.dayNames[d]).join(', ')} ohne Komfortzeit',
        detail: warmer
            ? 'An diesen Tagen gilt ganztags der Spar-Sollwert – der hier höher ist als Komfort.'
            : 'An diesen Tagen gilt ganztags der Spar-Sollwert${saving == null ? '' : ' (${t(saving)})'}. '
                'Wenn ihr dort zu Hause seid, wird es kühler als an den anderen Tagen.',
        action: FindingAction.fixScheduleDays,
      ));
    }
  }
  if (comfort != null && comfort > 22) {
    out.add(ConfigFinding(
      id: 'comfort_high',
      area: FindingArea.heating,
      severity: FindingSeverity.hint,
      title: 'Komfort-Sollwert ${t(comfort)} ist hoch',
      detail: 'Jedes Grad weniger spart etwa $_percentPerKelvin % Heizenergie. 20–21 °C reichen in Wohnräumen meist.',
      action: FindingAction.openCurveAssistant,
    ));
  }
  final curve = i.curve, ref = i.reference;
  if (curve != null && ref == null) {
    out.add(const ConfigFinding(
      id: 'no_building_profile',
      area: FindingArea.heating,
      severity: FindingSeverity.hint,
      title: 'Heizkurve nicht prüfbar – Gebäudetyp fehlt',
      detail: 'Mit Heizsystem und Baujahr vergleicht die App deine Heizkurve mit den Richtwerten von EnergieSchweiz.',
      action: FindingAction.pickBuildingProfile,
    ));
  }
  if (curve != null && ref != null) {
    final own = curve.flowAt(-8, 20);
    final high = ref.highAt(-8), low = ref.lowAt(-8);
    if (own > high + 1) {
      final excess = own - high;
      final roomK = (excess / (curve.slope * ControllerHeatingCurve.danfossRoomConstant)).clamp(0.0, 5.0);
      out.add(ConfigFinding(
        id: 'curve_high',
        area: FindingArea.heating,
        severity: excess > 8 ? FindingSeverity.warning : FindingSeverity.hint,
        title: 'Heizkurve höher als nötig',
        detail: 'Bei −8 °C liefert deine Kurve ${t(own)}, für ${ref.label} reichen ${t(low)}–${t(high)}. '
            'Das entspricht grob ${roomK.fixed(1)} °C mehr Raumtemperatur ≈ '
            '${(roomK * _percentPerKelvin).fixed(0)} % Heizenergie. Schrittweise absenken und beobachten.',
        action: FindingAction.openCurveAssistant,
      ));
    } else if (own < low - 2) {
      out.add(ConfigFinding(
        id: 'curve_low',
        area: FindingArea.heating,
        severity: FindingSeverity.hint,
        title: 'Heizkurve eher niedrig',
        detail: 'Bei −8 °C liefert deine Kurve ${t(own)}, Richtwert ${t(low)}–${t(high)}. Wenn es an kalten '
            'Tagen zu kühl wird, liegt es daran – sonst ist das sparsam und in Ordnung.',
        action: FindingAction.openCurveAssistant,
      ));
    }
    final maxFlow = i.maxFlow;
    if (maxFlow != null && ref.isFloorHeating && maxFlow > 45) {
      out.add(ConfigFinding(
        id: 'max_flow_floor',
        area: FindingArea.heating,
        severity: FindingSeverity.warning,
        title: 'Max. Vorlauf ${t(maxFlow)} bei Fußbodenheizung',
        detail: 'Fußbodenheizungen brauchen selten mehr als 35–40 °C; viele Estriche vertragen dauerhaft '
            'höchstens 45–55 °C. Die Begrenzung im Regler schützt vor zu heißem Vorlauf – ein Wert knapp über '
            'dem höchsten Punkt der Heizkurve (z. B. 45 °C) reicht. Im Zweifel den Installateur fragen.',
        action: FindingAction.setMaxFlow,
      ));
    }
  }
  final cutoff = i.summerCutoff;
  if (cutoff != null && cutoff > 17) {
    out.add(ConfigFinding(
      id: 'summer_cutoff_high',
      area: FindingArea.heating,
      severity: FindingSeverity.hint,
      title: 'Sommerabschaltung erst ab ${t(cutoff)}',
      detail: 'Bis zu dieser Außentemperatur wird geheizt. Für gut gedämmte Gebäude reichen meist 12–15 °C.',
    ));
  }

  // ── Hot water ──────────────────────────────────────────────────────
  final dhw = i.dhwComfort;
  final abOn = (i.antiBacteriaTemp ?? 9) > 9 && (i.antiBacteriaDays ?? 0) != 0;
  if (dhw != null && dhw < 50 && !abOn) {
    out.add(ConfigFinding(
      id: 'dhw_legionella',
      area: FindingArea.hotWater,
      severity: FindingSeverity.warning,
      title: 'Warmwasser ${t(dhw)} ohne Legionellenschutz',
      detail: 'Unter 50 °C im Speicher können sich Legionellen vermehren. Temperatur erhöhen oder den '
          'Legionellenschutz (z. B. 1× pro Woche 60 °C) einschalten.',
      action: FindingAction.openHotWater,
    ));
  }
  if (dhw != null && dhw > 60) {
    out.add(ConfigFinding(
      id: 'dhw_high',
      area: FindingArea.hotWater,
      severity: FindingSeverity.hint,
      title: 'Warmwasser ${t(dhw)} ist sehr heiß',
      detail: 'Höhere Speichertemperatur heißt höhere Verluste und Verbrühungsgefahr. 55–60 °C reichen in der Regel.',
      action: FindingAction.openHotWater,
    ));
  }
  if (i.dhwMode == 1 && dhw != null && i.dhwSaving != null && i.dhwSaving! > dhw) {
    out.add(ConfigFinding(
      id: 'dhw_saving_above',
      area: FindingArea.hotWater,
      severity: FindingSeverity.warning,
      title: 'Warmwasser-Spar höher als Komfort',
      detail: 'Spar ${t(i.dhwSaving!)}, Komfort ${t(dhw)} – außerhalb der Komfortzeiten wird heißer gehalten.',
      action: FindingAction.openHotWater,
    ));
  }
  if (abOn && (i.antiBacteriaDays ?? 0) == 127) {
    out.add(const ConfigFinding(
      id: 'legionella_daily',
      area: FindingArea.hotWater,
      severity: FindingSeverity.hint,
      title: 'Legionellenschutz läuft täglich',
      detail: 'Einmal pro Woche reicht für Einfamilienhäuser in der Regel – täglich kostet unnötig Energie.',
      action: FindingAction.openHotWater,
    ));
  }
  final circ = i.circulation;
  if (circ != null) {
    final nightDays = <int>[];
    var minutes = 0;
    for (var d = 0; d < 7; d++) {
      for (final p in circ.activePeriods(d)) {
        minutes += p.minutes;
        if (p.start < 500) nightDays.add(d);
      }
    }
    final perDay = minutes / 7 / 60;
    if (nightDays.isNotEmpty) {
      final days = nightDays.toSet().map((d) => WeekSchedule.dayShort[d]).join(', ');
      out.add(ConfigFinding(
        id: 'circulation_night',
        area: FindingArea.hotWater,
        severity: FindingSeverity.hint,
        title: 'Zirkulation läuft nachts ($days)',
        detail: 'Die Zirkulationspumpe startet vor 05:00 Uhr. Nachts wird selten Warmwasser gezapft – ein '
            'späterer Start spart Wärmeverluste der Leitung und Pumpenstrom.',
        action: FindingAction.openHotWater,
      ));
    }
    if (perDay > 16) {
      out.add(ConfigFinding(
        id: 'circulation_long',
        area: FindingArea.hotWater,
        severity: FindingSeverity.hint,
        title: 'Zirkulation ${perDay.fixed(0)} Std. pro Tag',
        detail: 'Die Leitung wird fast den ganzen Tag warm gehalten. Auf die Zeiten begrenzen, in denen '
            'wirklich gezapft wird (z. B. morgens und abends).',
        action: FindingAction.openHotWater,
      ));
    }
  }

  out.sort((a, b) => a.severity.index.compareTo(b.severity.index));
  return out;
}
