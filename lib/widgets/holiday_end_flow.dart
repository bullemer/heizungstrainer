import 'package:heizungstrainer/utils/number_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:heizungstrainer/models/holiday_plan.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/holiday_service.dart';

const _card = Color(0xFF2A2A32);
const _accentOrange = Color(0xFFFFA726);
const _ecoGreen = Color(0xFF66BB6A);

/// Asks, then ends [plan] and restores normal operation. If the restore
/// fails the plan stays active, with the option to close it without touching
/// the controller. Returns true if the plan was ended.
Future<bool> endHolidayPlanWithConfirmation(
  BuildContext context, {
  required HolidayPlan plan,
  required HolidayService service,
  required ECLProvider provider,
}) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _card,
      title: Text(plan.setbackApplied ? 'Abwesenheitsmodus beenden?' : 'Geplante Abwesenheit verwerfen?'),
      content: Text(plan.setbackApplied
          ? (plan.controlMode == 'room'
              ? 'Der Raum-Sollwert geht sofort zurück auf ${plan.normalRoomTemp.fixed(1)} °C.'
              : 'Die Heizung schaltet sofort wieder auf die normalen Komfort-Einstellungen um.')
          : 'Die Heizung wurde noch nicht abgesenkt; der Plan wird verworfen.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton(
          key: const Key('confirmEndHoliday'),
          style: FilledButton.styleFrom(backgroundColor: _accentOrange),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(plan.setbackApplied ? 'Jetzt beenden' : 'Verwerfen'),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return false;

  HapticFeedback.mediumImpact();
  try {
    await service.cancelOrFinishPlan(plan: plan, provider: provider);
  } catch (e) {
    if (!context.mounted) return false;
    final manual = plan.controlMode == 'room'
        ? 'den Raum-Sollwert bitte selbst auf ${plan.normalRoomTemp.fixed(1)} °C'
        : 'die Parallelverschiebung bitte selbst auf ${plan.normalShift.fixed(0)}';
    final closeAnyway = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Normalbetrieb nicht wiederhergestellt'),
        content: Text(
          '$e\n\nDu kannst es erneut versuchen, sobald der Regler erreichbar ist. '
          'Oder den Plan ohne Änderung am Regler schließen – dann stell $manual zurück.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Plan aktiv lassen')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ohne Zurücksetzen schließen')),
        ],
      ),
    );
    if (closeAnyway == true) {
      await service.cancelOrFinishPlan(plan: plan, provider: provider, restore: false);
      return true;
    }
    return false;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(plan.setbackApplied
          ? (plan.controlMode == 'room'
              ? '✓ Normalbetrieb: Raum-Sollwert wieder ${plan.normalRoomTemp.fixed(1)} °C.'
              : '✓ Normalbetrieb wiederhergestellt.')
          : '✓ Geplante Abwesenheit verworfen.'),
    ));
  }
  return true;
}

String _when(DateTime t) {
  final now = DateTime.now();
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final today = t.year == now.year && t.month == now.month && t.day == now.day;
  return today ? 'heute $hm' : '${t.day}.${t.month}. $hm';
}

/// Start-page card for an active (or armed) holiday plan with an end button.
/// Renders nothing when no plan is active.
class ActiveHolidayCard extends StatefulWidget {
  final ECLProvider provider;
  final HolidayService? service;

  const ActiveHolidayCard({super.key, required this.provider, this.service});

  @override
  State<ActiveHolidayCard> createState() => _ActiveHolidayCardState();
}

class _ActiveHolidayCardState extends State<ActiveHolidayCard> {
  late final HolidayService _service;
  HolidayPlan? _plan;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? HolidayService();
    HolidayService.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    HolidayService.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final plan = await _service.getActivePlan();
    if (mounted) setState(() => _plan = plan);
  }

  Future<void> _end() async {
    final plan = _plan;
    if (plan == null) return;
    setState(() => _busy = true);
    await endHolidayPlanWithConfirmation(context, plan: plan, service: _service, provider: widget.provider);
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    if (plan == null) return const SizedBox.shrink();
    final armed = !plan.setbackApplied;
    final heatUp = plan.preheatStartTime;
    final controllerEnd = DateTime(heatUp.year, heatUp.month, heatUp.day);
    final what = plan.runsInController
        ? 'Im Regler (P${plan.controllerSlot}): Spar ${plan.targetRoomTemp.fixed(1)} °C statt ${plan.normalRoomTemp.fixed(1)} °C'
        : armed
        ? 'Geplant ab ${_when(plan.startDateTime)}'
        : (plan.controlMode == 'room'
            ? 'Raum-Sollwert auf ${plan.targetRoomTemp.fixed(1)} °C (normal ${plan.normalRoomTemp.fixed(1)} °C)'
            : 'Parallelverschiebung ${plan.setbackShift.fixed(0)} (normal ${plan.normalShift.fixed(0)})');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: const Key('activeHolidayCard'),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: _ecoGreen.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _ecoGreen.withValues(alpha: 0.55)),
        ),
        child: Row(children: [
          const Icon(Icons.beach_access_rounded, color: _ecoGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Urlaubsmodus aktiv: ${plan.title}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 3),
                Text(what, style: const TextStyle(fontSize: 12, color: Color(0xFFBDBDC7))),
                Text(
                  plan.runsInController
                      ? 'Rückkehr ${_when(plan.endDateTime)} · Normalbetrieb ab ${_when(controllerEnd)}'
                      : 'Rückkehr ${_when(plan.endDateTime)} · Vorheizen ab ${_when(plan.preheatStartTime)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFBDBDC7)),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('endHolidayFromHome'),
            onPressed: _busy ? null : _end,
            child: Text(armed && !plan.runsInController ? 'Verwerfen' : 'Beenden'),
          ),
        ]),
      ),
    );
  }
}
