import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/exceptions/license_exception.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/curve_optimizer_service.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';
import 'package:heizungstrainer/widgets/controller_curve_chart.dart';
import 'package:heizungstrainer/widgets/pro_upgrade_dialog.dart';

/// Shows the controller's real heating curve, simulates a different comfort
/// room setpoint (curve + rough savings) and runs the step-by-step assistant.
class CurveSimulatorScreen extends StatefulWidget {
  final CurveOptimizerService? optimizer;

  const CurveSimulatorScreen({super.key, this.optimizer});

  @override
  State<CurveSimulatorScreen> createState() => _CurveSimulatorScreenState();
}

class _CurveSimulatorScreenState extends State<CurveSimulatorScreen> {
  static const _card = Color(0xFF2A2A32);
  static const _border = Color(0xFF3A3A44);
  static const _green = Color(0xFF66BB6A);

  late final CurveOptimizerService _optimizer;
  final _annualController = TextEditingController();

  double? _simSetpoint;
  OptimizerState _opt = OptimizerState.idle;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _optimizer = widget.optimizer ?? CurveOptimizerService();
    _load();
  }

  @override
  void dispose() {
    _annualController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = context.read<ECLProvider>();
    final opt = await _optimizer.load();
    await provider.refreshSavingsInputs();
    if (!mounted) return;
    setState(() {
      _opt = opt;
      final manual = provider.annualHeatingKwhManual;
      if (manual != null) _annualController.text = manual.toStringAsFixed(0);
    });
  }

  double? get _annualKwh => context.read<ECLProvider>().annualHeatingKwh;
  double? get _price => context.read<ECLProvider>().pricePerKwhCached;

  Future<void> _saveAnnual(String text) => context
      .read<ECLProvider>()
      .setAnnualHeatingKwh(double.tryParse(text.replaceAll('.', '').replaceAll(',', '.')));

  /// Writes [setpoint]; returns true on a confirmed write.
  Future<bool> _write(double setpoint) async {
    final provider = context.read<ECLProvider>();
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      await provider.writeParameter(ECLRegisters.roomTargetTemp, setpoint);
      return true;
    } on LicenseRequiredException {
      if (mounted) {
        await ProUpgradeDialog.show(context, featureHint: 'Das Ändern des Raum-Sollwerts');
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(userFacingError(e, fallback: 'Fehler beim Schreiben')),
          backgroundColor: const Color(0xFFEF5350),
        ));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Assistant actions ────────────────────────────────────────────────────

  Future<void> _startAssistant(double current) async {
    final first = CurveOptimizerService.nextStep(current);
    if (first == null) return;
    if (!await _write(first)) return;
    final s = CurveOptimizerService.started(from: current, firstStep: first, now: DateTime.now());
    await _optimizer.save(s);
    if (mounted) setState(() => _opt = s);
  }

  Future<void> _feedbackComfortable() async {
    final next = CurveOptimizerService.nextStep(_opt.currentSetpoint!);
    if (next != null && !await _write(next)) return;
    final s = CurveOptimizerService.comfortable(_opt, nextSetpoint: next, now: DateTime.now());
    await _optimizer.save(s);
    if (mounted) setState(() => _opt = s);
  }

  Future<void> _feedbackTooCold() async {
    if (!await _write(_opt.previousSetpoint!)) return;
    final s = CurveOptimizerService.tooCold(_opt);
    await _optimizer.save(s);
    if (mounted) setState(() => _opt = s);
  }

  Future<void> _resetAssistant() async {
    await _optimizer.save(OptimizerState.idle);
    if (mounted) setState(() => _opt = OptimizerState.idle);
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ECLProvider>();
    final curve = ControllerHeatingCurve.fromReadings(provider.getReading);
    final room = provider.getReading(ECLRegisters.roomTargetTemp)?.displayValue;
    final outdoor = provider.getReading(ECLRegisters.outdoorTemp);
    final outdoorTemp = (outdoor != null && !outdoor.isSensorDisconnected) ? outdoor.displayValue : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Heizkurve & Sparrechner')),
      body: (curve == null || room == null)
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Dieser Regler stellt seine Heizkurve (Kurvenpunkte und Neigung) '
                'oder den Komfort-Raumsollwert nicht über Modbus bereit. Die '
                'Simulation braucht beides.',
              ),
            )
          : _buildContent(provider, curve, room, outdoorTemp),
    );
  }

  Widget _buildContent(ECLProvider provider, ControllerHeatingCurve curve, double room, double? outdoorTemp) {
    final sim = (_simSetpoint ?? room).clamp(16.0, 26.0).toDouble();
    final savings = RoomTemperatureSavings.estimate(
      currentSetpoint: room,
      newSetpoint: sim,
      annualHeatingKwh: _annualKwh,
      pricePerKwh: _price,
    );
    final atOutdoor = outdoorTemp ?? 0;
    final flowNow = curve.flowAt(atOutdoor, room);
    final flowSim = curve.flowAt(atOutdoor, sim);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section(
          title: 'Deine Heizkurve',
          subtitle: 'Gelesen aus dem Regler: Neigung ${curve.slope.toStringAsFixed(1)}, '
              'Komfort-Raumsollwert ${room.toStringAsFixed(1)} °C'
              '${curve.minFlow != null ? ', Vorlauf ${curve.minFlow!.toStringAsFixed(0)}–${curve.maxFlow?.toStringAsFixed(0) ?? '?'} °C' : ''}.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ControllerCurveChart(curve: curve, roomSetpoint: room, simulatedSetpoint: sim, outdoorTemp: outdoorTemp, reference: provider.buildingReference),
              const SizedBox(height: 8),
              Wrap(spacing: 16, children: [
                _legend(ControllerCurveChart.currentColor, 'Heizkurve im Regler'),
                if ((room - 20).abs() >= 0.25)
                  _legend(ControllerCurveChart.currentColor.withValues(alpha: 0.7), 'Wirksam bei ${room.toStringAsFixed(1)} °C'),
                if ((sim - room).abs() >= 0.25) _legend(ControllerCurveChart.simulatedColor, 'Simuliert (${sim.toStringAsFixed(1)} °C)'),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _section(
          title: 'Simulation: Raum-Sollwert ändern',
          subtitle: 'Danfoss verschiebt die Kurve um (Sollwert − 20) × Neigung × 2,5 K.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Slider(
                value: sim,
                min: 16,
                max: 26,
                divisions: 20,
                label: '${sim.toStringAsFixed(1)} °C',
                onChanged: (v) => setState(() => _simSetpoint = v),
              ),
              Text(
                outdoorTemp == null
                    ? 'Vorlauf bei 0 °C außen: ${flowNow.toStringAsFixed(1)} → ${flowSim.toStringAsFixed(1)} °C'
                    : 'Vorlauf jetzt (${outdoorTemp.toStringAsFixed(1)} °C außen): '
                        '${flowNow.toStringAsFixed(1)} → ${flowSim.toStringAsFixed(1)} °C',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              _savingsBox(savings, sim, room),
              const SizedBox(height: 12),
              TextField(
                controller: _annualController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Heizenergie pro Jahr (kWh)',
                  helperText: provider.annualHeatingKwhManual == null && _annualKwh != null
                      ? '${provider.annualHeatingKwhSource}: ${_annualKwh!.toStringAsFixed(0)} kWh – oder eigenen Wert eintragen'
                      : 'Steht auf deiner Heizkostenabrechnung',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: _saveAnnual,
                onTapOutside: (_) => _saveAnnual(_annualController.text),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_busy || (sim - room).abs() < 0.25 || !provider.isConnected)
                      ? null
                      : () async {
                          if (await _write(sim) && mounted) {
                            setState(() => _simSetpoint = null);
                          }
                        },
                  child: Text('${sim.toStringAsFixed(1)} °C übernehmen'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _assistant(provider, room),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _savingsBox(RoomTemperatureSavings s, double sim, double room) {
    if ((sim - room).abs() < 0.25) {
      return const Text('Schieb den Regler, um eine andere Raumtemperatur zu simulieren.',
          style: TextStyle(color: Color(0xFF9E9EA8), fontSize: 13));
    }
    final saving = s.percent > 0;
    final color = saving ? _green : const Color(0xFFFF7043);
    final pct = s.percent.abs().toStringAsFixed(0);
    final parts = <String>[saving ? 'ca. $pct % weniger Heizenergie' : 'ca. $pct % mehr Heizenergie'];
    if (s.kwhPerYear != null) parts.add('≈ ${s.kwhPerYear!.abs().toStringAsFixed(0)} kWh/Jahr');
    if (s.euroPerYear != null) parts.add('≈ ${s.euroPerYear!.abs().toStringAsFixed(0)} €/Jahr');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(parts.join(' · '), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Schätzung nach Faustregel (~6 % je °C Raumtemperatur). Der tatsächliche '
            'Effekt hängt von Gebäude, Wetter und Nutzung ab.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF9E9EA8)),
          ),
        ],
      ),
    );
  }

  Widget _assistant(ECLProvider provider, double room) {
    final floor = provider.isFloorHeating;
    final wait = CurveOptimizerService.observationFor(floorHeating: floor);
    final phase = CurveOptimizerService.phaseOf(_opt, DateTime.now(), wait: wait);
    final connected = provider.isConnected && !_busy;
    late final String text;
    final actions = <Widget>[];

    switch (phase) {
      case OptimizerPhase.idle:
        final first = CurveOptimizerService.nextStep(room);
        text = 'Finde die niedrigste Einstellung, bei der es noch angenehm ist: Die App senkt '
            'den Komfort-Raumsollwert in Schritten von 0,5 °C. Nach jedem Schritt beobachtest du '
            '${floor ? 'vier Tage (Fußbodenheizung reagiert träge)' : 'zwei Tage'} lang den kältesten '
            'Raum (Thermostate/Stellantriebe dabei voll auf). Ist es zu kalt, geht sie einen Schritt '
            'zurück – das ist dann deine passende Kurve.';
        actions.add(FilledButton(
          onPressed: (connected && first != null) ? () => _startAssistant(room) : null,
          child: Text(first == null ? 'Untergrenze erreicht' : 'Starten: ${first.toStringAsFixed(1)} °C'),
        ));
      case OptimizerPhase.waiting:
        final left = wait - DateTime.now().difference(_opt.stepStartedAt!);
        text = 'Test läuft: ${_opt.currentSetpoint!.toStringAsFixed(1)} °C. Beobachte den kältesten Raum. '
            'Rückmeldung in ca. ${left.inHours} Std. – wird es vorher zu kalt, melde es gleich.';
        actions.add(OutlinedButton(onPressed: connected ? _feedbackTooCold : null, child: const Text('Zu kalt')));
      case OptimizerPhase.readyForFeedback:
        final next = CurveOptimizerService.nextStep(_opt.currentSetpoint!);
        text = 'Wie war es die letzten ${floor ? 'vier' : 'zwei'} Tage bei ${_opt.currentSetpoint!.toStringAsFixed(1)} °C?';
        actions.addAll([
          FilledButton(
            onPressed: connected ? _feedbackComfortable : null,
            child: Text(next == null ? 'Angenehm – fertig' : 'Angenehm → ${next.toStringAsFixed(1)} °C'),
          ),
          OutlinedButton(
            onPressed: connected ? _feedbackTooCold : null,
            child: Text('Zu kalt → ${_opt.previousSetpoint!.toStringAsFixed(1)} °C'),
          ),
        ]);
      case OptimizerPhase.finished:
        final result = _opt.resultSetpoint!;
        final s = RoomTemperatureSavings.estimate(
          currentSetpoint: _opt.startSetpoint ?? result,
          newSetpoint: result,
          annualHeatingKwh: _annualKwh,
          pricePerKwh: _price,
        );
        text = 'Ergebnis: ${result.toStringAsFixed(1)} °C ist für dein Gebäude passend'
            '${_opt.startSetpoint != null ? ' (vorher ${_opt.startSetpoint!.toStringAsFixed(1)} °C, grob ca. ${s.percent.toStringAsFixed(0)} % weniger Heizenergie)' : ''}. '
            'Bei deutlich kälterem Wetter lohnt eine erneute Prüfung.';
        actions.add(OutlinedButton(onPressed: _resetAssistant, child: const Text('Neu starten')));
    }

    return _section(
      title: 'Optimierungs-Assistent',
      subtitle: 'Methode nach EnergieSchweiz: in kleinen Schritten senken und beobachten.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
          if (phase == OptimizerPhase.waiting || phase == OptimizerPhase.readyForFeedback) ...[
            const SizedBox(height: 4),
            TextButton(onPressed: _resetAssistant, child: const Text('Assistent abbrechen')),
          ],
        ],
      ),
    );
  }

  Widget _legend(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 3, color: c),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFFBDBDC7))),
      ]);

  Widget _section({required String title, required String subtitle, required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF9E9EA8))),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}
