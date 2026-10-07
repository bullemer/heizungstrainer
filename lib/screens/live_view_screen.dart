import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/models/live_snapshot.dart';
import 'package:heizungstrainer/models/week_schedule.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/utils/number_format.dart';
import 'package:heizungstrainer/widgets/a247_diagram.dart';

/// "Anlage live": the plant diagram with measured and target values, pumps
/// and valves – refreshed every few seconds while the screen is open.
class LiveViewScreen extends StatefulWidget {
  const LiveViewScreen({super.key, this.refreshInterval = const Duration(seconds: 5)});

  final Duration refreshInterval;

  @override
  State<LiveViewScreen> createState() => _LiveViewScreenState();
}

class _LiveViewScreenState extends State<LiveViewScreen> {
  LiveSnapshot? _snapshot;
  bool _failed = false;
  bool _loading = false;
  Timer? _timer;

  static const _bg = Color(0xFF1E1E24);
  static const _card = Color(0xFF2A2A32);
  static const _border = Color(0xFF3A3A44);
  static const _text = Color(0xFFECECF0);
  static const _muted = Color(0xFF9E9EA8);
  static const _target = Color(0xFF64B5F6);
  static const _on = Color(0xFFFFA726);

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(widget.refreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    final snap = await context.read<ECLProvider>().readLiveSnapshot();
    _loading = false;
    if (!mounted) return;
    setState(() {
      if (snap != null) _snapshot = snap;
      _failed = snap == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Anlage live', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        actions: [
          if (snap != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${snap.simulated ? 'Demo · ' : ''}${_time(snap.at)}',
                  style: TextStyle(color: _failed ? const Color(0xFFEF5350) : _muted, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: snap == null
          ? Center(
              child: _failed
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Keine Live-Daten – ist der Regler verbunden?',
                          style: TextStyle(color: _muted), textAlign: TextAlign.center),
                    )
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: [
                _statusChips(snap),
                if (_failed)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Aktualisierung fehlgeschlagen – zeige letzten Stand.',
                        style: TextStyle(color: Color(0xFFEF5350), fontSize: 12)),
                  ),
                const SizedBox(height: 10),
                if (snap.spec.hasDiagram) ...[
                  Container(
                    key: const Key('liveDiagram'),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InteractiveViewer(
                      maxScale: 5,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: A247Diagram(snapshot: snap),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4, left: 4),
                    child: Text('Mit zwei Fingern vergrößern · Handy quer halten für mehr Platz',
                        style: TextStyle(color: _muted, fontSize: 11)),
                  ),
                ] else
                  _note('Für die Applikation ${snap.spec.application} gibt es noch kein Anlagenbild – '
                      'unten alle Werte des Reglers.'),
                if (snap.limiterTexts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _section('Was den Heizungs-Sollwert gerade beeinflusst', [
                    for (final t in snap.limiterTexts)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• $t', style: const TextStyle(color: _text, fontSize: 13)),
                      ),
                  ]),
                ],
                const SizedBox(height: 12),
                _section('Fühler (Ist / Soll)', [_sensorTable(snap)]),
                const SizedBox(height: 12),
                _section('Pumpen & Ventile', [_outputs(snap)]),
                const SizedBox(height: 8),
                const Text(
                  'Weiß = gemessen, blau in Klammern = Sollwert des Reglers (10.0 °C = „aus“). '
                  'Werte direkt aus dem Regler (Danfoss Modbus).',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  Widget _statusChips(LiveSnapshot s) {
    Widget chip(String label, String value) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$label ', style: const TextStyle(color: _muted, fontSize: 12)),
            TextSpan(text: value, style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
          ])),
        );
    return Wrap(spacing: 8, runSpacing: 6, children: [
      if (s.circuitMode.containsKey(1) || s.circuitStatus.containsKey(1))
        chip('Heizung', '${eclModeLabel(s.circuitMode[1]?.toDouble())} · ${eclStatusLabel(s.circuitStatus[1])}'),
      if (s.spec.hasDiagram && (s.circuitMode.containsKey(2) || s.circuitStatus.containsKey(2)))
        chip('Warmwasser', '${eclModeLabel(s.circuitMode[2]?.toDouble())} · ${eclStatusLabel(s.circuitStatus[2])}'),
      if (s.alarmOutput) chip('Alarm', 'aktiv'),
    ]);
  }

  Widget _section(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 13.5)),
          const SizedBox(height: 8),
          ...children,
        ]),
      );

  Widget _note(String t) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
        child: Text(t, style: const TextStyle(color: _muted, fontSize: 13)),
      );

  Widget _sensorTable(LiveSnapshot s) {
    const head = TextStyle(color: _muted, fontSize: 11.5);
    const cell = TextStyle(color: _text, fontSize: 12.5);
    final numbers = [
      for (var n = 1; n <= 10; n++)
        if (s.spec.sensorNames.containsKey(n) || (!s.spec.hasDiagram && s.sensors[n] != null)) n,
    ];
    return Table(
      columnWidths: const {0: FixedColumnWidth(34), 1: FlexColumnWidth(2.4), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1)},
      children: [
        const TableRow(children: [
          Text('', style: head),
          Text('Funktion', style: head),
          Text('Ist', style: head),
          Text('Soll', style: head),
        ]),
        for (final n in numbers)
          TableRow(children: [
            Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('S$n', style: cell.copyWith(fontWeight: FontWeight.w700))),
            Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(s.spec.sensorNames[n] ?? 'Fühler $n', style: cell)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(s.sensors[n] == null ? '--' : '${s.sensors[n]!.fixed(1)} °C', style: cell),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(s.references[n] == null ? '' : '${s.references[n]!.fixed(1)} °C',
                  style: cell.copyWith(color: _target)),
            ),
          ]),
      ],
    );
  }

  Widget _outputs(LiveSnapshot s) {
    Widget row(String id, String name, String state, bool active) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 34, child: Text(id, style: const TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 12.5))),
            Expanded(child: Text(name, style: const TextStyle(color: _text, fontSize: 12.5))),
            Text(state, style: TextStyle(color: active ? _on : _muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        );
    String valve(ValveMotion m) => switch (m) {
          ValveMotion.opening => 'öffnet',
          ValveMotion.closing => 'schließt',
          ValveMotion.idle => 'steht',
        };
    if (!s.spec.hasDiagram) {
      return Column(children: [
        for (var i = 1; i <= 6; i++) row('R$i', 'Relais $i', s.relay(i) ? 'an' : 'aus', s.relay(i)),
        for (var i = 1; i <= 6; i++) row('Tr$i', 'Triac $i', s.triac(i) ? 'an' : 'aus', s.triac(i)),
      ]);
    }
    return Column(children: [
      row('P1', 'Heizungspumpe', s.p1 ? 'läuft' : 'aus', s.p1),
      row('P2', 'Speicherladepumpe', s.p2 ? 'läuft' : 'aus', s.p2),
      row('P3', 'Zirkulationspumpe', s.p3 ? 'läuft' : 'aus', s.p3),
      row('M2', 'Ventil Heizung', valve(s.m2), s.m2 != ValveMotion.idle),
      row('M1', 'Ventil Warmwasser', valve(s.m1), s.m1 != ValveMotion.idle),
      row('A1', 'Alarmausgang', s.alarmOutput ? 'ALARM' : 'aus', s.alarmOutput),
    ]);
  }
}
