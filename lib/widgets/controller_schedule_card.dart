import 'package:heizungstrainer/utils/number_format.dart';
import 'package:flutter/material.dart';

import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/week_schedule.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';

/// Start page card: the controller's weekly comfort schedule, comfort and
/// saving setpoint – with warnings and one-tap fixes for typical mistakes
/// (a day without comfort period, saving setpoint above comfort).
class ControllerScheduleCard extends StatelessWidget {
  const ControllerScheduleCard({super.key, required this.provider});

  final ECLProvider provider;

  static const _accent = Color(0xFFFFA726);
  static const _warn = Color(0xFFFFB74D);
  static const _text = Color(0xFFECECF0);
  static const _muted = Color(0xFF9E9EA8);

  static String _t(double? v) => v == null ? '–' : '${v.fixed(v == v.roundToDouble() ? 0 : 1)} °C';

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

    return Container(
      key: const Key('controllerScheduleCard'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (savingTooHigh && emptyDays.isNotEmpty) ? _warn.withValues(alpha: 0.6) : const Color(0xFF3A3A44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.calendar_month_rounded, color: _accent, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Zeitprogramm im Regler',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: _text)),
            ),
            Text(eclModeLabel(mode), style: const TextStyle(color: _muted, fontSize: 11)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _chip('Komfort', _t(comfort), const Color(0xFF66BB6A)),
            const SizedBox(width: 8),
            _chip('Spar', _t(saving), savingTooHigh ? const Color(0xFFEF5350) : const Color(0xFF42A5F5)),
          ]),
          const SizedBox(height: 10),
          for (var d = 0; d < 7; d++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: 28, child: Text(WeekSchedule.dayShort[d], style: const TextStyle(color: _muted, fontSize: 12))),
                Expanded(
                  child: Text(
                    schedule.hasComfort(d)
                        ? 'Komfort ${schedule.describeDay(d)}'
                        : 'keine Komfortzeit → ganztags Spar ${_t(saving)}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: schedule.hasComfort(d) ? _text : _warn,
                      fontWeight: schedule.hasComfort(d) ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                ),
              ]),
            ),
          if (savingTooHigh) ...[
            const SizedBox(height: 10),
            _warning(
              'Der Spar-Sollwert (${_t(saving)}) ist höher als Komfort (${_t(comfort)}): '
              'außerhalb der Komfortzeiten heizt der Regler wärmer statt sparsamer.',
              button: TextButton(
                key: const Key('fixSaving'),
                onPressed: () => _fixSaving(context, comfort, saving),
                child: const Text('Spar-Sollwert ändern'),
              ),
            ),
          ],
          if (emptyDays.isNotEmpty && template != null) ...[
            const SizedBox(height: 8),
            _warning(
              '${emptyDays.map((d) => WeekSchedule.dayNames[d]).join(', ')} '
              '${emptyDays.length == 1 ? 'hat' : 'haben'} keine Komfortzeit – '
              'der Regler nutzt dort ganztags den Spar-Sollwert.',
              button: TextButton(
                key: const Key('fixEmptyDays'),
                onPressed: () => _fixDays(context, emptyDays, template),
                child: Text('Wie die anderen Tage (${template.where((p) => p.isActive).join(', ')})'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, String value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text('$label $value', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
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
      messenger.showSnackBar(SnackBar(content: Text(userFacingError(e)), backgroundColor: const Color(0xFFEF5350)));
    }
  }

  Future<void> _fixDays(BuildContext context, List<int> days, List<SchedulePeriod> template) async {
    final names = days.map((d) => WeekSchedule.dayNames[d]).join(', ');
    final plan = template.where((p) => p.isActive).join(', ');
    if (!await _confirm(context, 'Zeitprogramm ergänzen',
        '$names bekommt die Komfortzeit $plan – wie die anderen Tage. '
        'Danach gilt dort der Komfort-Sollwert statt des Spar-Sollwerts.\n\n'
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
    var value = (comfort - 3).clamp(10.0, comfort).roundToDouble();
    final chosen = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A32),
          title: const Text('Spar-Sollwert', style: TextStyle(color: _text, fontSize: 18)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Gilt außerhalb der Komfortzeiten. Üblich sind 2–4 °C unter Komfort (${_t(comfort)}). '
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
        'Spar-Sollwert auf ${_t(chosen)} gesetzt.');
  }
}
