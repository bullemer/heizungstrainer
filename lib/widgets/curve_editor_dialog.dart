import 'package:flutter/material.dart';

import 'package:heizungstrainer/exceptions/license_exception.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';
import 'package:heizungstrainer/utils/number_format.dart';
import 'package:heizungstrainer/widgets/pro_upgrade_dialog.dart';

/// "Heizkurve anpassen": makes the controller's curve flatter or steeper in
/// 5 % steps around 20 °C, keeping its shape, and writes the six points.
/// The table shows exactly the values that are written. (Writing the slope
/// instead would make the controller overwrite individually set points.)
Future<void> showCurveEditor(BuildContext context, ECLProvider provider) async {
  const card = Color(0xFF2A2A32);
  const text = Color(0xFFECECF0);
  const muted = Color(0xFF9E9EA8);
  const accent = Color(0xFFFFA726);
  const minPercent = -40, maxPercent = 40;

  final curve = ControllerHeatingCurve.fromReadings(provider.getReading);
  if (curve == null) return;
  final reference = provider.buildingReference;
  var percent = 0;

  final chosen = await showDialog<ControllerHeatingCurve>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final preview = curve.scaled(1 + percent / 100);
        final changed = [
          for (var i = 0; i < curve.flowTemps.length; i++) preview.flowTemps[i] != curve.flowTemps[i],
        ].any((c) => c);
        final cappedAt = curve.maxFlow != null && preview.flowTemps.first > curve.maxFlow! ? curve.maxFlow : null;
        TableRow row(int i) => TableRow(children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text('${curve.outdoorTemps[i].fixed(0)} °C', style: const TextStyle(color: muted, fontSize: 12.5)),
              ),
              Text('${curve.flowTemps[i].fixed(0)} °C', style: const TextStyle(color: text, fontSize: 12.5)),
              Text(
                '${preview.flowTemps[i].fixed(0)} °C',
                key: Key('curvePoint_$i'),
                style: TextStyle(
                  color: preview.flowTemps[i] == curve.flowTemps[i] ? muted : accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]);
        String label(int p) => p == 0 ? 'wie jetzt' : p < 0 ? '${-p} % flacher' : '$p % steiler';
        return AlertDialog(
          backgroundColor: card,
          title: const Text('Heizkurve anpassen', style: TextStyle(color: text, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'Flacher = weniger Vorlauf bei Kälte (sparsamer), steiler = wärmer bei Frost. '
                'Die Form deiner Kurve bleibt erhalten. Die Basis-Wärme verschiebt sie zusätzlich.',
                style: TextStyle(color: Color(0xFFB0B0BA), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton.filledTonal(
                  key: const Key('curveFlatter'),
                  tooltip: 'flacher',
                  onPressed: percent > minPercent ? () => setState(() => percent -= 5) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 130,
                  child: Text(label(percent),
                      key: const Key('curveChange'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: accent, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                IconButton.filledTonal(
                  key: const Key('curveSteeper'),
                  tooltip: 'steiler',
                  onPressed: percent < maxPercent ? () => setState(() => percent += 5) : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ]),
              const SizedBox(height: 12),
              Table(
                columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
                children: [
                  const TableRow(children: [
                    Text('Außen', style: TextStyle(color: muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    Text('Vorlauf jetzt', style: TextStyle(color: muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    Text('neu', style: TextStyle(color: muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ]),
                  for (var i = 0; i < curve.flowTemps.length; i++) row(i),
                ],
              ),
              const SizedBox(height: 6),
              const Text('Werte bei 20 °C Raum-Soll, wie im Regler gespeichert.',
                  style: TextStyle(color: muted, fontSize: 11)),
              if (cappedAt != null) ...[
                const SizedBox(height: 6),
                Text('Bei großer Kälte begrenzt „Max. Vorlauf“ auf ${cappedAt.fixed(0)} °C.',
                    style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 11.5)),
              ],
              if (reference != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Richtwert für ${reference.label}: ${reference.lowAtMinus8.fixed(0)}–'
                  '${reference.highAtMinus8.fixed(0)} °C bei −8 °C außen '
                  '(jetzt ${curve.flowAt(-8, 20).fixed(0)} °C, neu ${preview.flowAt(-8, 20).fixed(0)} °C).',
                  style: const TextStyle(color: muted, fontSize: 11.5, height: 1.35),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'In kleinen Schritten ändern und ein paar Tage beobachten, ob alle Räume warm genug werden.',
                style: TextStyle(color: muted, fontSize: 11.5, height: 1.35),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              key: const Key('saveCurve'),
              onPressed: changed ? () => Navigator.pop(ctx, preview) : null,
              style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
              child: const Text('An Regler senden'),
            ),
          ],
        );
      },
    ),
  );
  if (chosen == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final before = curve.flowTemps.map((f) => f.fixed(0)).join('/');
  try {
    await provider.writeHeatingCurve(chosen.flowTemps);
    final now = ControllerHeatingCurve.fromReadings(provider.getReading)?.flowTemps ?? chosen.flowTemps;
    messenger.showSnackBar(SnackBar(
      content: Text('Heizkurve übernommen: $before → ${now.map((f) => f.fixed(0)).join('/')} °C'),
      backgroundColor: const Color(0xFF66BB6A),
    ));
  } on LicenseRequiredException {
    if (context.mounted) {
      await ProUpgradeDialog.show(context, featureHint: 'Das Verstellen und Schreiben der Heizkurve');
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(userFacingError(e)), backgroundColor: const Color(0xFFEF5350)));
  }
}
