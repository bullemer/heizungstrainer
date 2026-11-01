import 'package:flutter/material.dart';

import 'package:heizungstrainer/models/week_schedule.dart';

/// Edits the three periods of one schedule day (heating comfort times,
/// circulation pump times). Returns the periods in Danfoss order –
/// chronological, unused ones as 24:00/24:00 at the end – and whether they
/// should apply to every day; null if cancelled or invalid (a snackbar then
/// says why).
Future<(List<SchedulePeriod>, bool)?> showScheduleDayEditor(
  BuildContext context, {
  required String title,
  required List<SchedulePeriod> initial,
}) async {
  const card = Color(0xFF2A2A32);
  const text = Color(0xFFECECF0);
  const muted = Color(0xFF9E9EA8);
  var periods = [for (final p in initial) p];
  var applyToAll = false;
  final times = [for (var h = 0; h <= 24; h++) ...[h * 100, if (h < 24) h * 100 + 30]];
  final result = await showDialog<(List<SchedulePeriod>, bool)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Widget timeBox(Key key, int value, ValueChanged<int> onChanged) => DropdownButton<int>(
              key: key,
              value: times.contains(value) ? value : 2400,
              isExpanded: true,
              dropdownColor: card,
              items: [for (final t in times) DropdownMenuItem(value: t, child: Text(SchedulePeriod.formatTime(t)))],
              onChanged: (v) => onChanged(v!),
            );
        return AlertDialog(
          backgroundColor: card,
          title: Text(title, style: const TextStyle(color: text, fontSize: 18)),
          content: SizedBox(
            width: 300,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < 3; i++)
                Row(children: [
                  SizedBox(width: 22, child: Text('${i + 1}.', style: const TextStyle(color: muted))),
                  Expanded(
                    child: timeBox(Key('periodStart_$i'), periods[i].start,
                        (v) => setState(() => periods[i] = SchedulePeriod(v, periods[i].stop))),
                  ),
                  const Text(' – ', style: TextStyle(color: muted)),
                  Expanded(
                    child: timeBox(Key('periodStop_$i'), periods[i].stop,
                        (v) => setState(() => periods[i] = SchedulePeriod(periods[i].start, v))),
                  ),
                ]),
              const Text('Gleiche Start- und Endzeit = Zeitraum aus.', style: TextStyle(color: muted, fontSize: 11.5)),
              CheckboxListTile(
                key: const Key('applyToAllDays'),
                contentPadding: EdgeInsets.zero,
                value: applyToAll,
                onChanged: (v) => setState(() => applyToAll = v ?? false),
                title: const Text('Für alle Tage übernehmen', style: TextStyle(color: text, fontSize: 13)),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              key: const Key('saveScheduleDay'),
              onPressed: () => Navigator.pop(ctx, (periods, applyToAll)),
              child: const Text('An Regler senden'),
            ),
          ],
        );
      },
    ),
  );
  if (result == null || !context.mounted) return null;
  final error = scheduleDayError(result.$1);
  if (error != null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error), backgroundColor: const Color(0xFFEF5350)));
    return null;
  }
  return (normalizeScheduleDay(result.$1), result.$2);
}

/// Why the periods can't be written, or null if they can.
String? scheduleDayError(List<SchedulePeriod> periods) {
  if (periods.any((p) => p.start > p.stop)) {
    return 'Zeiträume über Mitternacht gehen nicht – bitte aufteilen, z. B. 22:00–24:00 '
        'und am nächsten Tag 00:00–06:00.';
  }
  final active = [for (final p in periods) if (p.isActive) p]..sort((a, b) => a.start.compareTo(b.start));
  for (var i = 1; i < active.length; i++) {
    if (active[i].start < active[i - 1].stop) return 'Die Zeiträume überschneiden sich.';
  }
  return null;
}

/// Danfoss rules: chronological, inactive periods as 2400/2400 at the end.
List<SchedulePeriod> normalizeScheduleDay(List<SchedulePeriod> periods) {
  final active = [for (final p in periods) if (p.isActive) p]..sort((a, b) => a.start.compareTo(b.start));
  return [...active, for (var i = active.length; i < 3; i++) SchedulePeriod.unused];
}
