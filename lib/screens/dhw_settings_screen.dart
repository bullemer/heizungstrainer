import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/week_schedule.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/circulation_profiles.dart';
import 'package:heizungstrainer/utils/number_format.dart';

/// Hot-water settings of the controller: mode, comfort/saving temperature,
/// legionella protection and circulation pump times. Every change asks
/// first, is written, read back and logged. (No hot-water holiday on purpose.)
class DhwSettingsScreen extends StatelessWidget {
  const DhwSettingsScreen({super.key});

  static const _bg = Color(0xFF1E1E24);
  static const _card = Color(0xFF2A2A32);
  static const _border = Color(0xFF3A3A44);
  static const _text = Color(0xFFECECF0);
  static const _muted = Color(0xFF9E9EA8);
  static const _accent = Color(0xFF42A5F5);
  static const _warn = Color(0xFFFFB74D);

  static const _dayBits = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ECLProvider>();
    double? v(ECLParameter p) => provider.getReading(p)?.displayValue;
    final comfort = v(ECLRegisters.dhwComfortSetpoint);
    final saving = v(ECLRegisters.dhwSavingSetpoint);
    final mode = v(ECLRegisters.dhwMode)?.round();
    final abTemp = v(ECLRegisters.antiBacteriaTemp)?.round();
    final abDays = v(ECLRegisters.antiBacteriaDays)?.round() ?? 0;
    final abStart = v(ECLRegisters.antiBacteriaStart)?.round() ?? 0;
    final abDuration = v(ECLRegisters.antiBacteriaDuration)?.round();
    final abOn = abTemp != null && abTemp > 9 && abDays != 0;
    final circulation = provider.circulationSchedule;
    final tank = v(ECLRegisters.hotWaterTemp);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('Warmwasser', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
      body: !provider.supportsDhwSettings
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Warmwasser-Einstellungen gibt es nur mit verbundenem Danfoss ECL 310 (Applikation A247).',
                    textAlign: TextAlign.center, style: TextStyle(color: _muted)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
              children: [
                if (tank != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('Speicher oben jetzt: ${tank.fixed(1)} °C',
                        style: const TextStyle(color: _muted, fontSize: 13)),
                  ),
                _section('Betriebsart', [
                  SegmentedButton<int>(
                    key: const Key('dhwMode'),
                    segments: const [
                      ButtonSegment(value: 1, label: Text('Zeitplan')),
                      ButtonSegment(value: 2, label: Text('Komfort')),
                      ButtonSegment(value: 3, label: Text('Spar')),
                    ],
                    selected: {if (mode != null && mode >= 1 && mode <= 3) mode},
                    emptySelectionAllowed: true,
                    showSelectedIcon: false,
                    onSelectionChanged: (sel) {
                      if (sel.isEmpty) return;
                      final m = sel.first;
                      const labels = {1: 'Zeitplan', 2: 'Immer Komfort', 3: 'Immer Spar'};
                      _write(context, provider, ECLRegisters.dhwMode, m.toDouble(),
                          'Betriebsart Warmwasser auf „${labels[m]}“ setzen?');
                    },
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Zeitplan: Komfort-Temperatur in den Komfortzeiten, sonst Spar. '
                    'Komfort / Spar: rund um die Uhr diese Temperatur.',
                    style: TextStyle(color: _muted, fontSize: 11.5),
                  ),
                ]),
                const SizedBox(height: 12),
                _section('Temperaturen', [
                  _valueRow(context, 'Komfort', comfort, () =>
                      _pickTemperature(context, provider, ECLRegisters.dhwComfortSetpoint, comfort ?? 55, 45, 65)),
                  _valueRow(context, 'Spar', saving, () =>
                      _pickTemperature(context, provider, ECLRegisters.dhwSavingSetpoint, saving ?? 50, 40, comfort ?? 65)),
                  if (comfort != null && comfort < 50)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Unter 50 °C im Speicher können sich Legionellen vermehren – dann den '
                        'Legionellenschutz einschalten.',
                        style: TextStyle(color: _warn, fontSize: 12),
                      ),
                    ),
                ]),
                const SizedBox(height: 12),
                _section('Legionellenschutz', [
                  Row(children: [
                    Expanded(
                      child: Text(
                        abOn
                            ? '$abTemp °C · ${_daysText(abDays)} ab ${_halfHour(abStart)} · ${abDuration ?? 120} min'
                            : 'aus',
                        style: const TextStyle(color: _text, fontSize: 13.5),
                      ),
                    ),
                    Switch(
                      key: const Key('abSwitch'),
                      value: abOn,
                      onChanged: (on) => on
                          ? _enableAntiBacteria(context, provider, abDays, abStart)
                          : _write(context, provider, ECLRegisters.antiBacteriaTemp, 9,
                              'Legionellenschutz ausschalten?'),
                    ),
                  ]),
                  const Text(
                    'Heizt den Speicher regelmäßig hoch (z. B. 1× pro Woche auf 60 °C). '
                    'Kostet etwas Energie, sinnvoll vor allem bei Warmwasser unter 55 °C.',
                    style: TextStyle(color: _muted, fontSize: 11.5),
                  ),
                ]),
                const SizedBox(height: 12),
                _section('Zirkulationspumpe (P3)', [
                  if (circulation == null)
                    const Text('Zeiten werden gelesen …', style: TextStyle(color: _muted))
                  else
                    for (var d = 0; d < 7; d++)
                      InkWell(
                        key: Key('circ_$d'),
                        onTap: () => _editCirculationDay(context, provider, d, circulation),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(children: [
                            SizedBox(width: 30, child: Text(WeekSchedule.dayShort[d], style: const TextStyle(color: _muted))),
                            Expanded(
                              child: Text(
                                circulation.hasComfort(d) ? circulation.describeDay(d) : 'aus',
                                style: const TextStyle(color: _text, fontSize: 13),
                              ),
                            ),
                            const Icon(Icons.edit_outlined, size: 16, color: _muted),
                          ]),
                        ),
                      ),
                  const SizedBox(height: 6),
                  if (circulation != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        key: const Key('circOptimal'),
                        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                        label: Text('Optimale Zeiten (jetzt ${circulationHoursPerDay(circulation).fixed(0)} Std./Tag)'),
                        onPressed: () => _optimalCirculation(context, provider, circulation),
                      ),
                    ),
                  const SizedBox(height: 6),
                  const Text(
                    'Die Zirkulation hält nur die Leitung zur Zapfstelle warm. Außerhalb der Zeiten gibt es '
                    'trotzdem Warmwasser – es dauert nur etwas länger, bis es warm aus dem Hahn kommt. '
                    'Jede Stunde weniger spart Wärme und etwas Pumpenstrom.',
                    style: TextStyle(color: _muted, fontSize: 11.5),
                  ),
                ]),
              ],
            ),
    );
  }

  static String _halfHour(int slot) =>
      '${(slot ~/ 2).toString().padLeft(2, '0')}:${slot.isOdd ? '30' : '00'}';

  static String _daysText(int mask) {
    if (mask == 127) return 'täglich';
    return [for (var i = 0; i < 7; i++) if (mask & (1 << i) != 0) _dayBits[i]].join(', ');
  }

  Widget _section(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          ...children,
        ]),
      );

  Widget _valueRow(BuildContext context, String label, double? value, VoidCallback onEdit) => InkWell(
        onTap: value == null ? null : onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(color: _text, fontSize: 13.5))),
            Text(value == null ? '–' : '${value.fixed(0)} °C',
                style: const TextStyle(color: _accent, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            const Icon(Icons.edit_outlined, size: 16, color: _muted),
          ]),
        ),
      );

  static Future<bool> _confirm(BuildContext context, String question) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _card,
          content: Text('$question\n\nWird an den Regler gesendet, zurückgelesen und protokolliert.',
              style: const TextStyle(color: _text, fontSize: 14, height: 1.4)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('An Regler senden')),
          ],
        ),
      ) ==
      true;

  static Future<void> _run(BuildContext context, Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done), backgroundColor: const Color(0xFF66BB6A)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(userFacingError(e)), backgroundColor: const Color(0xFFEF5350)));
    }
  }

  static Future<void> _write(
      BuildContext context, ECLProvider provider, ECLParameter p, double value, String question) async {
    if (!await _confirm(context, question) || !context.mounted) return;
    await _run(context, () => provider.writeParameter(p, value), 'Übernommen.');
  }

  static Future<void> _pickTemperature(
      BuildContext context, ECLProvider provider, ECLParameter p, double current, double min, double max) async {
    var value = current.clamp(min, max).roundToDouble();
    final chosen = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: _card,
          title: Text(p.name, style: const TextStyle(color: _text, fontSize: 18)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${value.fixed(0)} °C', style: const TextStyle(color: _accent, fontSize: 24, fontWeight: FontWeight.w700)),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: (max - min).round(),
              onChanged: (v) => setState(() => value = v.roundToDouble()),
            ),
            const Text('Je 5 °C weniger spart etwa 5–8 % Warmwasser-Energie (Speicher- und Leitungsverluste).',
                style: TextStyle(color: _muted, fontSize: 11.5)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, value), child: const Text('An Regler senden')),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    await _run(context, () => provider.writeParameter(p, chosen), '${p.name}: ${chosen.fixed(0)} °C');
  }

  static Future<void> _enableAntiBacteria(BuildContext context, ECLProvider provider, int days, int start) async {
    if (!await _confirm(context,
            'Legionellenschutz einschalten: jeden Montag ab 03:00 Uhr für 120 Minuten auf 60 °C?') ||
        !context.mounted) {
      return;
    }
    await _run(context, () async {
      // days and time first, the temperature (which switches it on) last
      await provider.writeParameter(ECLRegisters.antiBacteriaDays, 1); // Monday
      await provider.writeParameter(ECLRegisters.antiBacteriaStart, 6); // 03:00
      await provider.writeParameter(ECLRegisters.antiBacteriaDuration, 120);
      await provider.writeParameter(ECLRegisters.antiBacteriaTemp, 60);
    }, 'Legionellenschutz eingeschaltet (Mo 03:00, 60 °C).');
  }

  static String _profileTimes(CirculationProfile p) =>
      'Mo–Fr ${p.weekday.join(', ')} · Sa/So ${p.weekend.join(', ')}';

  static Future<void> _optimalCirculation(BuildContext context, ECLProvider provider, WeekSchedule current) async {
    final now = circulationHoursPerDay(current);
    final price = provider.pricePerKwhCached;
    final chosen = await showModalBottomSheet<CirculationProfile>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Optimale Zirkulationszeiten', style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Jetzt läuft die Pumpe ${now.fixed(1)} Std. pro Tag. Wähle, was zu euch passt:',
                style: const TextStyle(color: _muted, fontSize: 12.5)),
            const SizedBox(height: 12),
            for (final p in CirculationProfile.profiles) ...[
              () {
                final hours = circulationHoursPerDay(p.schedule);
                final saving = circulationSavingKwh(now - hours);
                final money = price == null || price <= 0
                    ? ''
                    : ' ≈ ${(saving.low * price).fixed(0)}–${(saving.high * price).fixed(0)} €';
                return InkWell(
                  key: Key('profile_${p.id}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(ctx, p),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E24),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.title, style: const TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 14.5)),
                      Text(p.description, style: const TextStyle(color: _muted, fontSize: 12)),
                      const SizedBox(height: 6),
                      Text(_profileTimes(p), style: const TextStyle(color: _text, fontSize: 12.5)),
                      const SizedBox(height: 4),
                      Text(
                        hours < now
                            ? '${hours.fixed(1)} Std./Tag statt ${now.fixed(1)} · spart ca. '
                                '${saving.low.fixed(0)}–${saving.high.fixed(0)} kWh Wärme/Jahr$money'
                            : '${hours.fixed(1)} Std./Tag – nicht weniger als jetzt',
                        style: TextStyle(color: hours < now ? const Color(0xFF66BB6A) : _muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                );
              }(),
            ],
            const Text(
              'Schätzung: gedämmte Zirkulationsleitung von ca. 20 m verliert 100–200 W, solange die Pumpe läuft. '
              'Dazu kommt etwas Pumpenstrom. Einzelne Tage kannst du danach weiter anpassen.',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ]),
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    if (!await _confirm(context, 'Zirkulationszeiten „${chosen.title}“ übernehmen?\n${_profileTimes(chosen)}') ||
        !context.mounted) {
      return;
    }
    await _run(context, () async {
      for (var d = 0; d < 7; d++) {
        final target = chosen.periodsFor(d);
        final day = provider.circulationSchedule ?? current;
        if (day.sameDay(chosen.schedule, d)) continue;
        await provider.writeCirculationDay(d, target);
      }
    }, 'Zirkulationszeiten „${chosen.title}“ übernommen.');
  }

  static Future<void> _editCirculationDay(
      BuildContext context, ECLProvider provider, int day, WeekSchedule schedule) async {
    var periods = [for (final p in schedule.days[day]) p];
    var applyToAll = false;
    final times = [for (var h = 0; h <= 24; h++) ...[h * 100, if (h < 24) h * 100 + 30]];
    final result = await showDialog<(List<SchedulePeriod>, bool)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          Widget timeBox(int value, ValueChanged<int> onChanged) => DropdownButton<int>(
                value: times.contains(value) ? value : 2400,
                isExpanded: true,
                dropdownColor: _card,
                items: [for (final t in times) DropdownMenuItem(value: t, child: Text(SchedulePeriod.formatTime(t)))],
                onChanged: (v) => onChanged(v!),
              );
          return AlertDialog(
            backgroundColor: _card,
            title: Text('Zirkulation ${WeekSchedule.dayNames[day]}', style: const TextStyle(color: _text, fontSize: 18)),
            content: SizedBox(width: 300, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < 3; i++)
                Row(children: [
                  SizedBox(width: 22, child: Text('${i + 1}.', style: const TextStyle(color: _muted))),
                  Expanded(child: timeBox(periods[i].start, (v) => setState(() => periods[i] = SchedulePeriod(v, periods[i].stop)))),
                  const Text(' – ', style: TextStyle(color: _muted)),
                  Expanded(child: timeBox(periods[i].stop, (v) => setState(() => periods[i] = SchedulePeriod(periods[i].start, v)))),
                ]),
              const Text('Gleiche Start- und Endzeit = Zeitraum aus.', style: TextStyle(color: _muted, fontSize: 11.5)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: applyToAll,
                onChanged: (v) => setState(() => applyToAll = v ?? false),
                title: const Text('Für alle Tage übernehmen', style: TextStyle(color: _text, fontSize: 13)),
              ),
            ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
              FilledButton(onPressed: () => Navigator.pop(ctx, (periods, applyToAll)), child: const Text('An Regler senden')),
            ],
          );
        },
      ),
    );
    if (result == null || !context.mounted) return;
    // Danfoss rules: chronological, inactive periods as 2400/2400 at the end
    final active = [for (final p in result.$1) if (p.isActive) p]..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < active.length; i++) {
      if (active[i].start < active[i - 1].stop) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Die Zeiträume überschneiden sich.'),
          backgroundColor: Color(0xFFEF5350),
        ));
        return;
      }
    }
    final normalized = [...active, for (var i = active.length; i < 3; i++) SchedulePeriod.unused];
    final days = result.$2 ? [for (var d = 0; d < 7; d++) d] : [day];
    await _run(context, () async {
      for (final d in days) {
        await provider.writeCirculationDay(d, normalized);
      }
    }, 'Zirkulationszeiten übernommen.');
  }
}
