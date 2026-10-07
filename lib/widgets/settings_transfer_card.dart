import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:heizungstrainer/app_version.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/settings_transfer_service.dart';

/// Settings card: export all app settings to a file and import them again
/// (new phone, or switching from the website APK to the Play version).
class SettingsTransferCard extends StatelessWidget {
  const SettingsTransferCard({
    super.key,
    required this.provider,
    this.service,
    this.saveFile,
    this.pickFile,
  });

  final ECLProvider provider;
  final SettingsTransferService? service;

  /// Test seams; default to the system file dialogs.
  final Future<bool> Function(String fileName, String content)? saveFile;
  final Future<String?> Function()? pickFile;

  static const _accent = Color(0xFFFFA726);

  SettingsTransferService get _service => service ?? SettingsTransferService();

  static Future<bool> _systemSave(String fileName, String content) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
      mimeType: 'application/json',
      dialogTitle: 'Einstellungen speichern',
    );
    return uri != null;
  }

  static Future<String?> _systemPick() async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Einstellungsdatei wählen');
    if (files.isEmpty) return null;
    return files.first.xFile.readAsString();
  }

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await _service.exportJson(appVersion: appVersionLabel);
      final now = DateTime.now();
      final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final saved = await (saveFile ?? _systemSave)('heizungstrainer-einstellungen-$date.json', json);
      if (saved) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Einstellungen gespeichert (ohne Passwörter).'),
          backgroundColor: Color(0xFF66BB6A),
        ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Export fehlgeschlagen: $e'),
        backgroundColor: const Color(0xFFEF5350),
      ));
    }
  }

  Future<void> _import(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A32),
        title: const Text('Einstellungen importieren?',
            style: TextStyle(color: Color(0xFFECECF0), fontSize: 18)),
        content: const Text(
          'Übernimmt Regler, Gebäudetyp, Preise, eigene Sicherungen und Urlaubspläne aus '
          'einer Einstellungsdatei. Vorhandene Werte werden überschrieben; Sicherungen und '
          'Urlaubspläne werden ergänzt.\n\nAn den Regler wird dabei nichts gesendet.',
          style: TextStyle(color: Color(0xFFB0B0BA), fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
            child: const Text('Datei wählen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final content = await (pickFile ?? _systemPick)();
      if (content == null) return;
      final result = await _service.importJson(content);
      await provider.reloadSettings();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A32),
          title: const Text('Einstellungen übernommen',
              style: TextStyle(color: Color(0xFFECECF0), fontSize: 18)),
          content: Text(
            '${result.imported.length} Einstellungen importiert.\n\n'
            'Bitte jetzt noch neu eingeben:\n'
            '• Zugangsdaten für dein Abrechnungsportal (z. B. Brunata)\n'
            '• Passwörter/Tokens für Viessmann, Bosch/Buderus oder Vaillant\n'
            '• Schreibfreigabe für Beta-Regler (falls genutzt)',
            style: const TextStyle(color: Color(0xFFB0B0BA), fontSize: 13.5, height: 1.4),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.black),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on SettingsFormatException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: const Color(0xFFEF5350),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Import fehlgeschlagen: $e'),
        backgroundColor: const Color(0xFFEF5350),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: _accent,
      side: BorderSide(color: _accent.withValues(alpha: 0.6)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A34),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.import_export_rounded, color: _accent, size: 20),
              SizedBox(width: 8),
              Text(
                'Einstellungen übertragen',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFECECF0)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Für ein neues Handy oder den Wechsel zur Play-Store-Version: Einstellungen, '
            'Sicherungen und Urlaubspläne als Datei sichern. Passwörter werden nicht gespeichert.',
            style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('settings_export'),
                style: buttonStyle,
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('Exportieren'),
                onPressed: () => _export(context),
              ),
              OutlinedButton.icon(
                key: const ValueKey('settings_import'),
                style: buttonStyle,
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                label: const Text('Importieren'),
                onPressed: () => _import(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
