import 'package:flutter/material.dart';

import 'package:heizungstrainer/services/alert_center.dart';

/// "Aktive Meldungen" at the top of the Logs tab.
class AlertsPanel extends StatelessWidget {
  const AlertsPanel({super.key, required this.alerts});

  final AlertCenter alerts;

  static Color _color(AlertSeverity s) => switch (s) {
        AlertSeverity.error => const Color(0xFFEF5350),
        AlertSeverity.warning => const Color(0xFFFFB74D),
        AlertSeverity.info => const Color(0xFF42A5F5),
      };

  static IconData _icon(AlertSeverity s) => switch (s) {
        AlertSeverity.error => Icons.error_outline_rounded,
        AlertSeverity.warning => Icons.warning_amber_rounded,
        AlertSeverity.info => Icons.info_outline_rounded,
      };

  static String _time(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}. '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: alerts,
      builder: (context, _) {
        final list = alerts.alerts;
        if (list.isEmpty) {
          return const Padding(
            key: Key('alertsNone'),
            padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              Icon(Icons.check_circle_outline_rounded, color: Color(0xFF66BB6A), size: 18),
              SizedBox(width: 8),
              Text('Keine aktiven Meldungen', style: TextStyle(color: Color(0xFF66BB6A), fontSize: 13)),
            ]),
          );
        }
        final open = alerts.unacknowledgedCount;
        return Container(
          key: const Key('alertsPanel'),
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A32),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: open > 0 ? const Color(0xFFEF5350).withValues(alpha: 0.5) : const Color(0xFF3A3A44)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.notifications_active_outlined, color: Color(0xFFFFA726), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aktive Meldungen (${list.length}${open > 0 ? ', $open neu' : ''})',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFFECECF0)),
                  ),
                ),
                if (open > 0)
                  TextButton(
                    key: const Key('alertsAckAll'),
                    onPressed: alerts.acknowledgeAll,
                    child: const Text('Alle gesehen'),
                  ),
              ]),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 230),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [for (final a in list) _row(a)],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(AppAlert a) {
    final c = _color(a.severity);
    return Opacity(
      opacity: a.acknowledged ? 0.6 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(_icon(a.severity), color: c, size: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(a.title, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
                if (a.isCondition) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                    child: Text('aktiv', style: TextStyle(color: c, fontSize: 9.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
              Text(a.message, style: const TextStyle(color: Color(0xFFD0D0D8), fontSize: 12, height: 1.3)),
              Text(
                a.isCondition && a.lastAt != a.firstAt ? 'seit ${_time(a.firstAt)}' : _time(a.firstAt),
                style: const TextStyle(color: Color(0xFF9E9EA8), fontSize: 10.5),
              ),
            ]),
          ),
          if (!a.acknowledged)
            TextButton(
              key: Key('alertAck_${a.key}'),
              onPressed: () => alerts.acknowledge(a.key),
              style: TextButton.styleFrom(minimumSize: const Size(40, 30), padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('OK'),
            ),
        ]),
      ),
    );
  }
}
