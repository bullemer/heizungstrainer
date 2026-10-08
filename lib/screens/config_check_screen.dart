import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/curve_simulator_screen.dart';
import 'package:heizungstrainer/screens/dhw_settings_screen.dart';
import 'package:heizungstrainer/screens/live_view_screen.dart';
import 'package:heizungstrainer/services/config_check.dart';
import 'package:heizungstrainer/widgets/building_profile_picker.dart';
import 'package:heizungstrainer/widgets/controller_schedule_card.dart';

/// Colors and labels shared by the check card and screen.
abstract final class FindingStyle {
  static Color color(FindingSeverity s) => switch (s) {
        FindingSeverity.problem => const Color(0xFFEF5350),
        FindingSeverity.warning => const Color(0xFFFFB74D),
        FindingSeverity.hint => const Color(0xFF42A5F5),
      };
  static IconData icon(FindingSeverity s) => switch (s) {
        FindingSeverity.problem => Icons.error_outline_rounded,
        FindingSeverity.warning => Icons.warning_amber_rounded,
        FindingSeverity.hint => Icons.lightbulb_outline_rounded,
      };
  static String area(FindingArea a) => switch (a) {
        FindingArea.heating => 'Heizung',
        FindingArea.hotWater => 'Warmwasser',
        FindingArea.controller => 'Regler',
      };
  static String? actionLabel(FindingAction a) => switch (a) {
        FindingAction.fixSavingSetpoint => 'Spar-Sollwert ändern',
        FindingAction.fixScheduleDays => 'Wie die anderen Tage',
        FindingAction.openCurveAssistant => 'Heizkurve optimieren',
        FindingAction.pickBuildingProfile => 'Gebäudetyp wählen',
        FindingAction.openHotWater => 'Warmwasser einstellen',
        FindingAction.openLiveView => 'Anlage live',
        FindingAction.none => null,
      };

  static Future<void> run(BuildContext context, ECLProvider provider, FindingAction a) async {
    switch (a) {
      case FindingAction.fixSavingSetpoint:
        await ControllerScheduleCard.fixSavingFor(context, provider);
      case FindingAction.fixScheduleDays:
        await ControllerScheduleCard.fixEmptyDaysFor(context, provider);
      case FindingAction.openCurveAssistant:
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CurveSimulatorScreen()));
      case FindingAction.pickBuildingProfile:
        await showBuildingProfilePicker(context, provider);
      case FindingAction.openHotWater:
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DhwSettingsScreen()));
      case FindingAction.openLiveView:
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveViewScreen()));
      case FindingAction.none:
        break;
    }
  }
}

/// All findings of the Einstellungs-Check, grouped by area.
class ConfigCheckScreen extends StatelessWidget {
  const ConfigCheckScreen({super.key});

  static const _card = Color(0xFF2A2A32);
  static const _text = Color(0xFFECECF0);
  static const _muted = Color(0xFF9E9EA8);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ECLProvider>();
    final findings = provider.configFindings;
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E24),
      appBar: AppBar(title: const Text('Einstellungs-Check', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
        children: [
          const Text(
            'Die App prüft die Einstellungen deines Reglers auf typische Fehler und Sparpotenzial. '
            'Nichts wird automatisch geändert.',
            style: TextStyle(color: _muted, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          if (findings.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Row(children: [
                Icon(Icons.check_circle_outline_rounded, color: Color(0xFF66BB6A)),
                SizedBox(width: 10),
                Expanded(child: Text('Keine Auffälligkeiten gefunden.', style: TextStyle(color: Color(0xFF66BB6A), fontSize: 15))),
              ]),
            ),
          for (final area in FindingArea.values)
            if (findings.any((f) => f.area == area)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: Text(FindingStyle.area(area), style: const TextStyle(color: _muted, fontWeight: FontWeight.w700)),
              ),
              for (final f in findings.where((f) => f.area == area)) _tile(context, provider, f),
            ],
          if (provider.dismissedFindingsCount > 0)
            TextButton(
              onPressed: provider.resetDismissedFindings,
              child: Text('${provider.dismissedFindingsCount} ausgeblendete Hinweise wieder anzeigen'),
            ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, ECLProvider provider, ConfigFinding f) {
    final c = FindingStyle.color(f.severity);
    final label = FindingStyle.actionLabel(f.action);
    return Container(
      key: Key('finding_${f.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(FindingStyle.icon(f.severity), color: c, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(f.title, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 14))),
        ]),
        const SizedBox(height: 6),
        Text(f.detail, style: const TextStyle(color: _text, fontSize: 12.5, height: 1.35)),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(alignment: WrapAlignment.end, children: [
            TextButton(
              onPressed: () => provider.dismissFinding(f.id),
              child: const Text('Ist so gewollt', style: TextStyle(color: _muted)),
            ),
            if (label != null)
              TextButton(onPressed: () => FindingStyle.run(context, provider, f.action), child: Text(label)),
          ]),
        ),
      ]),
    );
  }
}

/// Start page summary: counts and the most important findings.
class ConfigCheckCard extends StatelessWidget {
  const ConfigCheckCard({super.key, required this.provider});

  final ECLProvider provider;

  @override
  Widget build(BuildContext context) {
    final findings = provider.configFindings;
    final problems = findings.where((f) => f.severity == FindingSeverity.problem).length;
    final warnings = findings.where((f) => f.severity == FindingSeverity.warning).length;
    final hints = findings.length - problems - warnings;
    final worst = findings.isEmpty ? null : findings.first.severity;
    final color = worst == null ? const Color(0xFF66BB6A) : FindingStyle.color(worst);
    final summary = findings.isEmpty
        ? 'Keine Auffälligkeiten'
        : [
            if (problems > 0) '$problems ${problems == 1 ? 'Problem' : 'Probleme'}',
            if (warnings > 0) '$warnings ${warnings == 1 ? 'Warnung' : 'Warnungen'}',
            if (hints > 0) '$hints ${hints == 1 ? 'Hinweis' : 'Hinweise'}',
          ].join(' · ');
    return Material(
      color: const Color(0xFF2A2A32),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('openConfigCheck'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConfigCheckScreen())),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: findings.isEmpty ? 0.3 : 0.6)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(findings.isEmpty ? Icons.verified_outlined : Icons.fact_check_outlined, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Einstellungs-Check',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFFECECF0))),
                  Text(summary, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF9E9EA8)),
            ]),
            for (final f in findings.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 32),
                child: Row(children: [
                  Icon(FindingStyle.icon(f.severity), size: 14, color: FindingStyle.color(f.severity)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(f.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFFD0D0D8))),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
