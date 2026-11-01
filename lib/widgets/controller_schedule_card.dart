import 'package:heizungstrainer/utils/number_format.dart';
import 'package:flutter/material.dart';

import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/week_schedule.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/widgets/pro_upgrade_dialog.dart';
import 'package:heizungstrainer/widgets/schedule_day_editor.dart';

/// Start page card "Wann soll es warm sein?": the controller's weekly comfort
/// schedule as a 0–24 h timeline per day (warm = comfort setpoint, rest =
/// saving setpoint), what it saves, presets, every day and the saving
/// setpoint editable, and one-tap fixes for typical mistakes.
class ControllerScheduleCard extends StatelessWidget {
  const ControllerScheduleCard({super.key, required this.provider});

  final ECLProvider provider;

  static const _accent = Color(0xFFFFA726);
  static const _warn = Color(0xFFFFB74D);
  static const _text = Color(0xFFECECF0);
  static const _muted = Color(0xFF9E9EA8);

  static String _t(double? v) => v == null ? '–' : '${v.de(v == v.roundToDouble() ? 0 : 1)} °C';

  static const _warmColor = Color(0xFFFF8A50);
  static const _lowColor = Color(0xFF42A5F5);

  @override
  Widget build(BuildContext context) {
    final schedule = provider.controllerSchedule;
    if (schedule == null) return const SizedBox.shrink();
    final comfort = provider.getReading(ECLRegisters.roomTargetTemp)?.displayValue;
    final saving = provider.getReading(ECLRegisters.savingRoomTemp)?.displayValue;
    final mode = provider.getReading(ECLRegisters.circuitMode)?.displayValue;
    final template = schedule.mostCommonDay;
    final emptyDays = [for (var d = 0; d < 7; d++) if (!schedule.hasComfort(d)) d];
    final savingTooHigh = comfort != null && saving != null && saving > comfort;
    final kelvin = comfort != null && saving != null ? comfort - saving : null;
    final lowered = schedule.loweredHoursPerWeek;
    final scheduleIgnored = mode != null && mode.round() != 1;

    return Container(
      key: const Key('controllerScheduleCard'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (savingTooHigh || emptyDays.isNotEmpty) ? _warn.withValues(alpha: 0.6) : const Color(0xFF3A3A44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.schedule_rounded, color: _accent, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text('Wann soll es warm sein?',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _text)),
            ),
          ]),
          const SizedBox(height: 4),
          const Text(
            'Zu den warmen Zeiten heizt der Regler auf die Basis-Wärme, sonst senkt er ab. '
            'Absenken, wenn alle schlafen oder niemand zu Hause ist, spart Energie.',
            style: TextStyle(color: _muted, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip('Warm', _t(comfort), _warmColor),
            InkWell(
              key: const Key('editSaving'),
              borderRadius: BorderRadius.circular(8),
              onTap: comfort != null && saving != null ? () => _fixSaving(context, comfort, saving) : null,
              child: _chip('Abgesenkt', '${_t(saving)}  ✎', savingTooHigh ? const Color(0xFFEF5350) : _lowColor),
            ),
          ]),
          const SizedBox(height: 12),
          for (var d = 0; d < 7; d++)
            InkWell(
              key: Key('scheduleDay_$d'),
              borderRadius: BorderRadius.circular(6),
              onTap: () => _editDay(context, d, schedule),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 26, child: Text(WeekSchedule.dayShort[d], style: const TextStyle(color: _muted, fontSize: 12))),
                  Expanded(child: _timeline(schedule.activePeriods(d))),
                  SizedBox(
                    width: 92,
                    child: Text(
                      _dayText(schedule.activePeriods(d)),
                      key: Key('scheduleDayText_$d'),
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11.5, color: schedule.hasComfort(d) ? _text : _warn),
                    ),
                  ),
                ]),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(left: 26, right: 92, top: 2),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('0', style: TextStyle(color: _muted, fontSize: 10)),
              Text('6', style: TextStyle(color: _muted, fontSize: 10)),
              Text('12', style: TextStyle(color: _muted, fontSize: 10)),
              Text('18', style: TextStyle(color: _muted, fontSize: 10)),
              Text('24', style: TextStyle(color: _muted, fontSize: 10)),
            ]),
          ),
          const SizedBox(height: 6),
          const Text('Tag antippen, um die Zeiten zu ändern.', style: TextStyle(color: _muted, fontSize: 11)),
          const SizedBox(height: 12),
          if (scheduleIgnored)
            _info('Der Regler steht auf „${eclModeLabel(mode)}“ – diese Zeiten werden gerade nicht genutzt.')
          else if (lowered < 0.5)
            _info(
              'Es wird nie abgesenkt, die Heizung hält rund um die Uhr ${_t(comfort)}. '
              '${kelvin != null && kelvin >= 1 ? 'Nachts absenken (22–6 Uhr) spart grob bis zu '
                  '${WeekSchedule.savingPercent(loweredHoursPerWeek: 56, kelvin: kelvin).de(0)} %.' : ''}',
            )
          else if (kelvin != null && kelvin >= 0 && kelvin < 1)
            _info(
              'Abgesenkt ist nur ${kelvin.de(1)} °C kühler als warm – das spart kaum etwas. '
              'Üblich sind 2–4 °C weniger (Wert „Abgesenkt“ antippen).',
            )
          else if (kelvin != null && kelvin > 0)
            _info(
              '${lowered.de(0)} Stunden pro Woche abgesenkt um ${kelvin.de(1)} °C: '
              'spart grob bis zu ${WeekSchedule.savingPercent(loweredHoursPerWeek: lowered, kelvin: kelvin).de(0)} % Heizenergie.',
            ),
          if (savingTooHigh) ...[
            const SizedBox(height: 8),
            _warning(
              '„Abgesenkt“ (${_t(saving)}) ist wärmer als „Warm“ (${_t(comfort)}): '
              'außerhalb der warmen Zeiten heizt der Regler mehr statt weniger.',
              button: TextButton(
                key: const Key('fixSaving'),
                onPressed: () => _fixSaving(context, comfort, saving),
                child: const Text('Absenkung ändern'),
              ),
            ),
          ],
          if (emptyDays.isNotEmpty && template != null) ...[
            const SizedBox(height: 8),
            _warning(
              '${emptyDays.map((d) => WeekSchedule.dayNames[d]).join(', ')} '
              '${emptyDays.length == 1 ? 'hat' : 'haben'} keine warme Zeit – '
              'dort bleibt es den ganzen Tag abgesenkt.',
              button: TextButton(
                key: const Key('fixEmptyDays'),
                onPressed: () => _fixDays(context, emptyDays, template),
                child: Text('Wie die anderen Tage (${template.where((p) => p.isActive).join(', ')})'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text('Vorlagen', style: TextStyle(color: _text, fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final preset in SchedulePreset.all)
              ChoiceChip(
                key: Key('schedulePreset_${preset.id}'),
                label: Text(preset.title),
                selected: schedule.sameAs(preset.schedule),
                onSelected: (_) => _applyPreset(context, preset, schedule),
              ),
          ]),
        ],
      ),
    );
  }

  static String _dayText(List<SchedulePeriod> active) {
    if (active.isEmpty) return 'nie warm';
    if (active.length == 1 && active.first == SchedulePeriod.allDay) return 'ganztags';
    String h(int hhmm) => hhmm % 100 == 0 ? '${hhmm ~/ 100}' : SchedulePeriod.formatTime(hhmm);
    return active.map((p) => '${h(p.start)}–${h(p.stop)}').join(', ');
  }

  /// 0–24 h bar: warm periods coloured, the rest (lowered) grey-blue.
  Widget _timeline(List<SchedulePeriod> active) => LayoutBuilder(
        builder: (context, box) {
          double x(int hhmm) => box.maxWidth * ((hhmm ~/ 100) * 60 + hhmm % 100) / (24 * 60);
          return Container(
            height: 14,
            decoration: BoxDecoration(
              color: _lowColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(children: [
              for (final p in active)
                Positioned(
                  left: x(p.start),
                  width: (x(p.stop) - x(p.start)).clamp(1.0, box.maxWidth),
                  top: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(color: _warmColor, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
            ]),
          );
        },
      );

  Widget _info(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _lowColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _lowColor.withValues(alpha: 0.3)),
        ),
        child: Text(text, key: const Key('scheduleInfo'), style: const TextStyle(color: _text, fontSize: 12, height: 1.35)),
      );

  Future<void> _applyPreset(BuildContext context, SchedulePreset preset, WeekSchedule current) async {
    if (current.sameAs(preset.schedule)) return;
    if (!await _confirm(context, 'Vorlage „${preset.title}“',
        '${preset.description}.\n\nDie geänderten Tage werden an den Regler gesendet, '
        'zurückgelesen und protokolliert.')) {
      return;
    }
    if (!context.mounted) return;
    await _run(context, () async {
      for (var d = 0; d < 7; d++) {
        final now = provider.controllerSchedule ?? current;
        if (now.sameDay(preset.schedule, d)) continue;
        await provider.writeScheduleDay(d, preset.periodsFor(d));
      }
    }, 'Vorlage „${preset.title}“ übernommen.');
  }

  Widget _chip(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text('$label $value', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _warning(String text, {required Widget button}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        decoration: BoxDecoration(
          color: _warn.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _warn.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('⚠️ $text', style: const TextStyle(color: _text, fontSize: 12.5, height: 1.35)),
          Align(alignment: Alignment.centerRight, child: button),
        ]),
      );

  Future<bool> _confirm(BuildContext context, String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A32),
          title: Text(title, style: const TextStyle(color: _text, fontSize: 18)),
          content: Text(body, style: const TextStyle(color: Color(0xFFB0B0BA), fontSize: 13.5, height: 1.4)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
              child: const Text('An Regler senden'),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _run(BuildContext context, Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done), backgroundColor: const Color(0xFF66BB6A)));
    } catch (e) {
      if (context.mounted) await showWriteError(context, e);
    }
  }

  /// Entry points for the Einstellungs-Check: same dialogs as the card.
  static Future<void> fixSavingFor(BuildContext context, ECLProvider provider) async {
    final comfort = provider.getReading(ECLRegisters.roomTargetTemp)?.displayValue;
    final saving = provider.getReading(ECLRegisters.savingRoomTemp)?.displayValue;
    if (comfort == null || saving == null) return;
    await ControllerScheduleCard(provider: provider)._fixSaving(context, comfort, saving);
  }

  static Future<void> fixEmptyDaysFor(BuildContext context, ECLProvider provider) async {
    final schedule = provider.controllerSchedule;
    final template = schedule?.mostCommonDay;
    if (schedule == null || template == null) return;
    final empty = [for (var d = 0; d < 7; d++) if (!schedule.hasComfort(d)) d];
    if (empty.isEmpty) return;
    await ControllerScheduleCard(provider: provider)._fixDays(context, empty, template);
  }

  Future<void> _editDay(BuildContext context, int day, WeekSchedule schedule) async {
    final result = await showScheduleDayEditor(
      context,
      title: 'Warm am ${WeekSchedule.dayNames[day]}',
      initial: schedule.days[day],
    );
    if (result == null || !context.mounted) return;
    final (periods, applyToAll) = result;
    final days = applyToAll ? [for (var d = 0; d < 7; d++) d] : [day];
    final active = periods.where((p) => p.isActive).join(', ');
    await _run(context, () async {
      for (final d in days) {
        final current = provider.controllerSchedule ?? schedule;
        if (current.withDay(d, periods).sameDay(current, d)) continue;
        await provider.writeScheduleDay(d, periods);
      }
    }, 'Zeitprogramm übernommen: ${applyToAll ? 'alle Tage' : WeekSchedule.dayNames[day]} '
        '${active.isEmpty ? 'ohne warme Zeit' : active}');
  }

  Future<void> _fixDays(BuildContext context, List<int> days, List<SchedulePeriod> template) async {
    final names = days.map((d) => WeekSchedule.dayNames[d]).join(', ');
    final plan = template.where((p) => p.isActive).join(', ');
    if (!await _confirm(context, 'Zeitprogramm ergänzen',
        '$names wird $plan warm – wie die anderen Tage – statt den ganzen Tag abgesenkt.\n\n'
        'Die Änderung wird an den Regler gesendet, zurückgelesen und protokolliert.')) {
      return;
    }
    if (!context.mounted) return;
    await _run(context, () async {
      for (final d in days) {
        await provider.writeScheduleDay(d, template);
      }
    }, 'Zeitprogramm übernommen: $names $plan');
  }

  Future<void> _fixSaving(BuildContext context, double comfort, double saving) async {
    // Start at the current value when it is sensible, else 3 °C below comfort.
    var value = ((saving <= comfort ? saving : comfort - 3).clamp(10.0, comfort) * 2).round() / 2;
    final chosen = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A32),
          title: const Text('Abgesenkte Temperatur', style: TextStyle(color: _text, fontSize: 18)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Gilt außerhalb der warmen Zeiten. Üblich sind 2–4 °C unter „Warm“ (${_t(comfort)}). '
              'Aktuell: ${_t(saving)}.',
              style: const TextStyle(color: Color(0xFFB0B0BA), fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            Center(child: Text(_t(value), style: const TextStyle(color: _accent, fontSize: 22, fontWeight: FontWeight.w700))),
            Slider(
              value: value,
              min: 10,
              max: comfort,
              divisions: ((comfort - 10) * 2).round(),
              onChanged: (v) => setState(() => value = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, value),
              style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
              child: const Text('An Regler senden'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    await _run(context, () => provider.writeParameter(ECLRegisters.savingRoomTemp, chosen),
        'Abgesenkt auf ${_t(chosen)} gesetzt.');
  }
}
