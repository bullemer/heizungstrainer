import 'package:heizungstrainer/utils/number_format.dart';
import 'package:flutter/material.dart';

import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';

/// Two-step selection (heating system × construction year / insulation
/// standard). Returns after saving; "Zurücksetzen" removes the profile.
Future<void> showBuildingProfilePicker(BuildContext context, ECLProvider provider) async {
  final result = await showModalBottomSheet<_PickerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF23232B),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _BuildingProfileSheet(initial: provider.buildingProfile),
  );
  if (result == null) return;
  await provider.setBuildingProfile(result.profile);
}

class _PickerResult {
  final BuildingProfile? profile;
  const _PickerResult(this.profile);
}

class _BuildingProfileSheet extends StatefulWidget {
  final BuildingProfile? initial;
  const _BuildingProfileSheet({required this.initial});

  @override
  State<_BuildingProfileSheet> createState() => _BuildingProfileSheetState();
}

class _BuildingProfileSheetState extends State<_BuildingProfileSheet> {
  HeatingSystem? _system;
  BuildingAge? _age;

  @override
  void initState() {
    super.initState();
    _system = widget.initial?.system;
    _age = widget.initial?.age;
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(fontSize: 12, color: Color(0xFF9E9EA8), height: 1.35);
    final complete = _system != null && _age != null;
    final preview = complete ? BuildingProfile(_system!, _age!) : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Dein Gebäude', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'Bestimmt den Richtwert-Bereich für die Heizkurve (EnergieSchweiz) und wie lange '
                'der Optimierungs-Assistent pro Schritt wartet.',
                style: muted,
              ),
              const SizedBox(height: 16),
              const Text('Heizsystem', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in HeatingSystem.values)
                  ChoiceChip(
                    key: Key('system_${s.name}'),
                    label: Text(s.label),
                    selected: _system == s,
                    onSelected: (_) => setState(() => _system = s),
                  ),
              ]),
              const SizedBox(height: 16),
              const Text('Baujahr bzw. Dämmstandard', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Bei sanierten Gebäuden das Jahr wählen, dessen Dämmstandard das Haus heute hat. '
                'Passivhaus/Minergie: „nach 2010“.',
                style: muted,
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in BuildingAge.values)
                  ChoiceChip(
                    key: Key('age_${a.name}'),
                    label: Text(a.label),
                    selected: _age == a,
                    onSelected: (_) => setState(() => _age = a),
                  ),
              ]),
              if (preview != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Richtwert Vorlauf bei −8 °C außen: '
                  '${preview.reference.lowAtMinus8.fixed(0)}–${preview.reference.highAtMinus8.fixed(0)} °C'
                  '${_system == HeatingSystem.mixed ? ' (Heizkörper-Werte, da sie die höhere Vorlauftemperatur brauchen)' : ''}.',
                  style: muted,
                ),
              ],
              const SizedBox(height: 20),
              Row(children: [
                if (widget.initial != null)
                  TextButton(
                    onPressed: () => Navigator.pop(context, const _PickerResult(null)),
                    child: const Text('Zurücksetzen'),
                  ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('saveBuildingProfile'),
                  onPressed: complete ? () => Navigator.pop(context, _PickerResult(preview)) : null,
                  child: const Text('Speichern'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top-of-page card showing the selected building (or a prompt to set it).
class BuildingProfileCard extends StatelessWidget {
  final ECLProvider provider;
  const BuildingProfileCard({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final profile = provider.buildingProfile;
    final missing = profile == null;
    const accent = Color(0xFFFFA726);
    return InkWell(
      key: const Key('buildingProfileCard'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => showBuildingProfilePicker(context, provider),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A32),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: missing ? accent.withValues(alpha: 0.6) : const Color(0xFF3A3A44)),
        ),
        child: Row(children: [
          Icon(missing ? Icons.home_work_outlined : Icons.home_rounded, color: accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Gebäudetyp', style: TextStyle(fontSize: 11.5, color: Color(0xFF9E9EA8))),
                const SizedBox(height: 2),
                Text(
                  missing ? 'Noch nicht festgelegt – für Richtwerte bitte wählen' : profile.label,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Text(missing ? 'Festlegen' : 'Ändern', style: const TextStyle(color: accent, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
