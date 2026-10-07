import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/configuration_backup.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/backup_service.dart';

/// Sicherungen (Time Machine) screen:
/// Allows creating configuration snapshots, reviewing saved points, and
/// restoring heating curves / controller parameters safely.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.backupService});

  final BackupService? backupService;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late final BackupService _backupService;
  List<ConfigurationBackup> _backups = [];
  bool _isRestoring = false;

  // ── Palette ──────────────────────────────────────────────────────────
  static const Color _background = Color(0xFF1E1E24);
  static const Color _card = Color(0xFF2A2A32);
  static const Color _border = Color(0xFF3A3A44);
  static const Color _accent = Color(0xFF00BFA5);
  static const Color _textPrimary = Color(0xFFEEEEEE);
  static const Color _textSecondary = Color(0xFF9E9EA8);

  @override
  void initState() {
    super.initState();
    _backupService = widget.backupService ?? BackupService();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    final list = await _backupService.getBackups();
    if (mounted) {
      setState(() {
        _backups = list;
      });
    }
  }

  /// 'room' when the controller is driven via the comfort room setpoint
  /// (no readable curve shift, e.g. ECL 310 applications without PNU 11176),
  /// otherwise 'shift'.
  String _modeOf(ECLProvider provider) =>
      provider.holidayControlMode == 'room' ? 'room' : 'shift';

  ECLParameter _paramFor(String mode) => mode == 'room'
      ? ECLRegisters.roomTargetTemp
      : ECLRegisters.heatingCurveShift;

  double? _currentValue(ECLProvider provider, String mode) =>
      provider.getReading(_paramFor(mode))?.displayValue;

  double? _backupValue(ConfigurationBackup backup) =>
      backup.isRoomMode ? backup.roomTarget : backup.heatingCurveShift;

  String _modeLabel(String mode) =>
      mode == 'room' ? 'Komfort-Raumsoll' : 'Parallelverschiebung';

  String _formatValue(double? value, String mode) {
    if (value == null) return '–';
    if (mode != 'room') return _formatShift(value);
    final digits = value == value.roundToDouble() ? 0 : 1;
    return '${value.toStringAsFixed(digits)} °C';
  }

  Future<void> _createBackup(ECLProvider provider) async {
    final mode = _modeOf(provider);
    final currentShift =
        provider.getReading(ECLRegisters.heatingCurveShift)?.displayValue;
    final currentValue = _currentValue(provider, mode);
    final outdoorTemp =
        provider.getReading(ECLRegisters.outdoorTemp)?.displayValue;
    final flowTemp = provider.getReading(ECLRegisters.flowTemp)?.displayValue;
    final returnTemp =
        provider.getReading(ECLRegisters.returnTemp)?.displayValue;
    final roomTarget =
        provider.getReading(ECLRegisters.roomTargetTemp)?.displayValue;

    final now = DateTime.now();
    final defaultTitle =
        'Sicherung ${_formatDateTimeShort(now)} (${mode == 'room' ? 'Raum' : 'Shift'} ${_formatValue(currentValue, mode)})';

    final nameController = TextEditingController(text: defaultTitle);
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.bookmark_add_rounded, color: _accent),
            SizedBox(width: 10),
            Text(
              'Neue Sicherung anlegen',
              style: TextStyle(color: _textPrimary, fontSize: 18),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sichere den aktuellen Zustand des Reglers als Wiederherstellungspunkt.',
                style: TextStyle(color: _textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                style: const TextStyle(color: _textPrimary),
                decoration: InputDecoration(
                  labelText: 'Bezeichnung',
                  labelStyle: const TextStyle(color: _textSecondary),
                  filled: true,
                  fillColor: const Color(0xFF22222A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                style: const TextStyle(color: _textPrimary),
                decoration: InputDecoration(
                  labelText: 'Notiz (optional)',
                  labelStyle: const TextStyle(color: _textSecondary),
                  hintText: 'z.B. vor Frostperiode getestet',
                  hintStyle: TextStyle(
                    color: _textSecondary.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF22222A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _accent.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gespeicherte Werte:',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• ${_modeLabel(mode)}: ${_formatValue(currentValue, mode)}\n'
                      '• Außentemperatur: ${outdoorTemp != null ? "${outdoorTemp.toStringAsFixed(1)} °C" : "–"}\n'
                      '• Vorlauftemperatur: ${flowTemp != null ? "${flowTemp.toStringAsFixed(1)} °C" : "–"}',
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen', style: TextStyle(color: _textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('Speichern', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final backup = ConfigurationBackup(
      id: 'backup_${DateTime.now().millisecondsSinceEpoch}',
      name: nameController.text.trim().isEmpty
          ? defaultTitle
          : nameController.text.trim(),
      timestamp: DateTime.now(),
      heatingCurveShift: currentShift ?? 0.0,
      roomTarget: roomTarget,
      controlMode: mode,
      outdoorTemp: outdoorTemp,
      flowTemp: flowTemp,
      returnTemp: returnTemp,
      note: noteController.text.trim().isEmpty
          ? null
          : noteController.text.trim(),
    );

    await _backupService.saveBackup(backup);
    await _loadBackups();

    if (mounted) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Konfiguration erfolgreich gesichert.'),
          backgroundColor: _accent,
        ),
      );
    }
  }

  Future<void> _restoreBackup(
    ConfigurationBackup backup,
    ECLProvider provider,
  ) async {
    if (!provider.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Regler nicht verbunden. Wiederherstellung nicht möglich.'),
          backgroundColor: Color(0xFFEF5350),
        ),
      );
      return;
    }

    final mode = _modeOf(provider);
    final targetValue = _backupValue(backup);
    if (backup.controlMode != mode || targetValue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Diese Sicherung enthält eine ${_modeLabel(backup.controlMode)}, '
            'der Regler wird aber über ${mode == 'room' ? 'den' : 'die'} ${_modeLabel(mode)} gesteuert.',
          ),
          backgroundColor: const Color(0xFFEF5350),
        ),
      );
      return;
    }
    final currentValue = _currentValue(provider, mode);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.restore_rounded, color: _accent),
            SizedBox(width: 10),
            Text(
              'Sicherung wiederherstellen',
              style: TextStyle(color: _textPrimary, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Möchtest du "${backup.name}" auf den Regler übertragen?',
              style: const TextStyle(color: _textPrimary, fontSize: 14),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E24),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Aktueller Reglerwert:',
                        style: TextStyle(color: _textSecondary, fontSize: 12),
                      ),
                      Text(
                        _formatValue(currentValue, mode),
                        style: const TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Neuer Wert aus Sicherung:',
                        style: TextStyle(color: _accent, fontSize: 12),
                      ),
                      Text(
                        _formatValue(targetValue, mode),
                        style: const TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen', style: TextStyle(color: _textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text(
              'Wiederherstellen',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRestoring = true);
    HapticFeedback.heavyImpact();

    try {
      await provider.writeParameter(_paramFor(mode), targetValue);

      if (mounted) {
        setState(() => _isRestoring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erfolgreich wiederhergestellt: ${_formatValue(targetValue, mode)}',
            ),
            backgroundColor: const Color(0xFF66BB6A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRestoring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Wiederherstellen: ${userFacingError(e)}'),
            backgroundColor: const Color(0xFFEF5350),
          ),
        );
      }
    }
  }

  Future<void> _deleteBackup(ConfigurationBackup backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sicherung löschen?', style: TextStyle(color: _textPrimary)),
        content: Text(
          'Möchtest du "${backup.name}" unwiderruflich löschen?',
          style: const TextStyle(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen', style: TextStyle(color: _textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF5350)),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _backupService.deleteBackup(backup.id);
      await _loadBackups();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ECLProvider>();
    final isConnected = provider.isConnected;
    final mode = _modeOf(provider);

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text(
          'Sicherungen',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _textSecondary),
            tooltip: 'Neu laden',
            onPressed: _loadBackups,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              children: [
                // ── Status & Snapshot Banner ──────────────────────────────
                _buildActiveStatusCard(provider, isConnected, mode),
                const SizedBox(height: 20),

                // ── Factory Presets ───────────────────────────────────────
                _buildSectionHeader('Vordefinierte Profile'),
                const SizedBox(height: 10),
                for (final preset in ConfigurationBackup.presetsFor(mode))
                  _buildPresetTile(preset, provider, isConnected, mode),

                const SizedBox(height: 24),

                // ── User Backups List ─────────────────────────────────────
                _buildSectionHeader('Eigene Sicherungen (${_backups.length})'),
                const SizedBox(height: 10),
                if (_backups.isEmpty)
                  _buildEmptyState()
                else
                  for (final b in _backups)
                    _buildBackupCard(b, provider, isConnected, mode),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildActiveStatusCard(
    ECLProvider provider,
    bool isConnected,
    String mode,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tune_rounded, color: _accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Aktiver Regler-Status',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      isConnected
                          ? 'Verbunden · ${_modeLabel(mode)} ${_formatValue(_currentValue(provider, mode), mode)}'
                          : 'Offline · Letzter bekannter Stand',
                      style: TextStyle(
                        color: isConnected ? const Color(0xFF66BB6A) : _textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isConnected && !_isRestoring
                  ? () => _createBackup(provider)
                  : null,
              icon: const Icon(Icons.bookmark_add_rounded, size: 18),
              label: const Text('Aktuelle Einstellung sichern'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetTile(
    ConfigurationBackup preset,
    ECLProvider provider,
    bool isConnected,
    String mode,
  ) {
    final current = _currentValue(provider, mode);
    final target = _backupValue(preset);
    final isCurrent = isConnected &&
        current != null &&
        target != null &&
        (current - target).abs() < 0.05;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent ? _accent.withValues(alpha: 0.5) : _border,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _formatValue(target, preset.controlMode),
              style: const TextStyle(
                color: _accent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      preset.name,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF66BB6A).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Aktiv',
                          style: TextStyle(
                            color: Color(0xFF66BB6A),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (preset.note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    preset.note!,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: isConnected && !isCurrent && !_isRestoring
                ? () => _restoreBackup(preset, provider)
                : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: _accent,
              side: BorderSide(
                color: isConnected && !isCurrent
                    ? _accent.withValues(alpha: 0.4)
                    : Colors.transparent,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(64, 34),
            ),
            child: const Text('Laden', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupCard(
    ConfigurationBackup backup,
    ECLProvider provider,
    bool isConnected,
    String mode,
  ) {
    final matchesMode = backup.controlMode == mode;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatValue(_backupValue(backup), backup.controlMode),
                  style: const TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      backup.name,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _formatDateTime(backup.timestamp),
                      style: const TextStyle(
                        color: _textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: _textSecondary, size: 20),
                tooltip: 'Löschen',
                onPressed: () => _deleteBackup(backup),
              ),
            ],
          ),
          if (backup.note != null && backup.note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              backup.note!,
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (backup.outdoorTemp != null || backup.flowTemp != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                if (backup.outdoorTemp != null)
                  Text(
                    'Außen: ${backup.outdoorTemp!.toStringAsFixed(1)} °C',
                    style: const TextStyle(color: _textSecondary, fontSize: 11),
                  ),
                if (backup.flowTemp != null)
                  Text(
                    'Vorlauf: ${backup.flowTemp!.toStringAsFixed(1)} °C',
                    style: const TextStyle(color: _textSecondary, fontSize: 11),
                  ),
              ],
            ),
          ],
          if (!matchesMode) ...[
            const SizedBox(height: 8),
            Text(
              'Gespeichert als ${_modeLabel(backup.controlMode)} – '
              'passt nicht zur aktuellen Steuerung (${_modeLabel(mode)}).',
              style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isConnected && matchesMode && !_isRestoring
                  ? () => _restoreBackup(backup, provider)
                  : null,
              icon: const Icon(Icons.restore_rounded, size: 16),
              label: const Text('Wiederherstellen'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: BorderSide(
                  color: isConnected && matchesMode
                      ? _accent.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.1),
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _card.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.cloud_queue_rounded,
            size: 40,
            color: _textSecondary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 10),
          const Text(
            'Noch keine eigenen Sicherungen',
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tippe auf "Aktuelle Einstellung sichern", um einen Wiederherstellungspunkt anzulegen. So kannst du neue Heizkurven risikolos ausprobieren.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _formatShift(double shift) {
    if (shift > 0) return '+${shift.toStringAsFixed(0)}';
    return shift.toStringAsFixed(0);
  }

  String _formatDateTime(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$day.$month.$year · $hour:$min Uhr';
  }

  String _formatDateTimeShort(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$day.$month. $hour:$min';
  }
}
