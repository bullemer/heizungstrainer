import 'package:flutter/material.dart';

import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/week_schedule.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/controller_settings_watch.dart';

/// "Regler abgleichen": reads all settings from the controller and shows
/// them next to the values the app knew. Differences are also in the log.
class SettingsCheckDialog extends StatefulWidget {
  const SettingsCheckDialog({super.key, required this.provider});

  final ECLProvider provider;

  static Future<void> show(BuildContext context, ECLProvider provider) {
    if (!provider.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nicht mit dem Regler verbunden.'),
        backgroundColor: Color(0xFFEF5350),
      ));
      return Future.value();
    }
    return showDialog<void>(context: context, builder: (_) => SettingsCheckDialog(provider: provider));
  }

  @override
  State<SettingsCheckDialog> createState() => _SettingsCheckDialogState();
}

class _SettingsCheckDialogState extends State<SettingsCheckDialog> {
  late final Future<List<SettingCheckRow>> _rows = widget.provider.checkControllerSettings();

  static const _muted = TextStyle(fontSize: 11.5, color: Color(0xFF9E9EA8));
  static const _cell = TextStyle(fontSize: 12.5, color: Color(0xFFECECF0));

  static String _fmt(double? v, String unit, [String? id]) {
    if (v == null) return '–';
    if (id == ECLRegisters.circuitMode.id) return eclModeLabel(v);
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return unit.isEmpty ? s : '$s $unit';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A32),
      title: const Text('Regler abgleichen', style: TextStyle(color: Color(0xFFECECF0), fontSize: 18)),
      content: SizedBox(
        width: double.maxFinite,
        child: FutureBuilder<List<SettingCheckRow>>(
          future: _rows,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return Text('Lesen fehlgeschlagen: ${snap.error}', style: _cell);
            }
            final rows = snap.data!;
            final diffs = rows.where((r) => r.differs).length;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    diffs == 0
                        ? 'Alle ${rows.length} Einstellungen im Regler stimmen mit dem Stand der App überein.'
                        : '$diffs von ${rows.length} Einstellungen weichen ab – Details im Protokoll.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: diffs == 0 ? const Color(0xFF66BB6A) : const Color(0xFFFFB74D),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Table(
                    columnWidths: const {0: FlexColumnWidth(1.6), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
                    children: [
                      const TableRow(children: [
                        Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Einstellung', style: _muted)),
                        Padding(padding: EdgeInsets.only(bottom: 6), child: Text('App', style: _muted)),
                        Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Regler', style: _muted)),
                      ]),
                      for (final r in rows)
                        TableRow(children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(r.parameter.name, style: _cell),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              _fmt(r.known?.value, r.parameter.unit, r.parameter.id) +
                                  (r.known?.source == SettingSource.app ? ' (App)' : ''),
                              style: _cell,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              _fmt(r.live, r.parameter.unit, r.parameter.id),
                              style: r.differs
                                  ? const TextStyle(fontSize: 12.5, color: Color(0xFFEF5350), fontWeight: FontWeight.w700)
                                  : _cell,
                            ),
                          ),
                        ]),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '„App“ = letzter Stand, den die App kannte; „(App)“ = von der App geschrieben. '
                    'Die Werte im Regler gelten ab jetzt als neuer Stand.',
                    style: _muted,
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFA726), foregroundColor: Colors.black),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
