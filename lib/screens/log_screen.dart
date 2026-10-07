import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/widgets/alerts_panel.dart';
import 'package:heizungstrainer/widgets/settings_check_dialog.dart';
import 'package:heizungstrainer/models/activity_log_entry.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';

/// Screen displaying user activities, controller read/write operations,
/// sensor fault monitoring (e.g. error 19200), and user-consented backoffice diagnostics.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final TextEditingController _searchController = TextEditingController();
  ActivityLogCategory? _selectedCategory;
  bool _errorsOnly = false;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ECLProvider>();
    final logService = provider.logService;

    return ListenableBuilder(
      listenable: logService,
      builder: (context, _) {
        final allEntries = logService.recentEntries;
        final filteredEntries = _filterEntries(allEntries);

        final totalCount = allEntries.length;
        final errorCount = allEntries.where((e) => e.level == ActivityLogLevel.error || e.errorCode != null).length;
        final writeCount = allEntries.where((e) => e.category == ActivityLogCategory.controllerWrite).length;
        final readCount = allEntries.where((e) => e.category == ActivityLogCategory.controllerRead).length;

        return Scaffold(
          appBar: AppBar(
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Aktivitäts- & Diagnoseprotokoll',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
                Text(
                  'Regler-Kommunikation · Fehlercodes · Überwachung',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9E9EA8)),
                ),
              ],
            ),
            actions: [
              IconButton(
                key: const Key('settings_check'),
                tooltip: 'Regler abgleichen',
                icon: const Icon(Icons.fact_check_outlined, color: Color(0xFFFFA726)),
                onPressed: () => SettingsCheckDialog.show(context, provider),
              ),
              IconButton(
                tooltip: 'Bericht an Backoffice senden',
                icon: const Icon(Icons.cloud_upload_outlined, color: Color(0xFFFFA726)),
                onPressed: () => _showBackofficeConsentDialog(context, provider),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  if (value == 'clear') {
                    _confirmClearLogs(context, logService);
                  } else if (value == 'copy_all') {
                    _copyAllLogsToClipboard(context, provider);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'copy_all',
                    child: Row(
                      children: [
                        Icon(Icons.copy_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Diagnosebericht kopieren'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'clear',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                        SizedBox(width: 8),
                        Text('Protokoll leeren', style: TextStyle(color: Colors.redAccent)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              // ── Active alerts ─────────────────────────────────────────
              AlertsPanel(alerts: provider.alerts),

              // ── KPI Summary Cards ─────────────────────────────────────
              _buildKpiBanner(
                total: totalCount,
                errors: errorCount,
                writes: writeCount,
                reads: readCount,
              ),

              // ── Search & Filter Chips ────────────────────────────────
              _buildFilterSection(),

              // ── Entries List ─────────────────────────────────────────
              Expanded(
                child: filteredEntries.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: filteredEntries.length,
                        itemBuilder: (context, index) {
                          final entry = filteredEntries[index];
                          return _LogItemCard(
                            key: ValueKey(entry.id ?? '${entry.timestamp.millisecondsSinceEpoch}_$index'),
                            entry: entry,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<ActivityLogEntry> _filterEntries(List<ActivityLogEntry> list) {
    return list.where((e) {
      if (_errorsOnly && e.level != ActivityLogLevel.error && e.errorCode == null) {
        return false;
      }
      if (_selectedCategory != null && e.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchMsg = e.message.toLowerCase().contains(query);
        final matchAction = e.action.toLowerCase().contains(query);
        final matchCode = e.errorCode?.toLowerCase().contains(query) ?? false;
        final matchCtrl = e.controllerId?.toLowerCase().contains(query) ?? false;
        if (!matchMsg && !matchAction && !matchCode && !matchCtrl) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Widget _buildKpiBanner({
    required int total,
    required int errors,
    required int writes,
    required int reads,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF24242C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A44)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildKpiItem('Gesamt', total.toString(), const Color(0xFFECECF0), Icons.receipt_long_rounded),
          _buildDivider(),
          _buildKpiItem('Fehler', errors.toString(), const Color(0xFFEF5350), Icons.error_outline_rounded),
          _buildDivider(),
          _buildKpiItem('Schreibbefehle', writes.toString(), const Color(0xFFB388FF), Icons.edit_note_rounded),
          _buildDivider(),
          _buildKpiItem('Messungen', reads.toString(), const Color(0xFF4ADE80), Icons.sensors_rounded),
        ],
      ),
    );
  }

  Widget _buildKpiItem(String title, String value, Color color, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF9E9EA8)),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 24,
      color: const Color(0xFF3A3A44),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          // Search text field
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'Nach Fehlercode (z.B. 19200), Regler oder Text filtern...',
              hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF7A7A85)),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF9E9EA8)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              filled: true,
              fillColor: const Color(0xFF2A2A32),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF3A3A44)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF3A3A44)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFFA726)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'Alle',
                  isSelected: !_errorsOnly && _selectedCategory == null,
                  onSelected: () => setState(() {
                    _errorsOnly = false;
                    _selectedCategory = null;
                  }),
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: 'Nur Fehler',
                  icon: Icons.error_outline_rounded,
                  color: const Color(0xFFEF5350),
                  isSelected: _errorsOnly,
                  onSelected: () => setState(() {
                    _errorsOnly = !_errorsOnly;
                  }),
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: 'Schreibbefehle',
                  icon: Icons.edit_note_rounded,
                  color: const Color(0xFFB388FF),
                  isSelected: _selectedCategory == ActivityLogCategory.controllerWrite,
                  onSelected: () => setState(() {
                    _selectedCategory = _selectedCategory == ActivityLogCategory.controllerWrite
                        ? null
                        : ActivityLogCategory.controllerWrite;
                  }),
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: 'Messwerte',
                  icon: Icons.sensors_rounded,
                  color: const Color(0xFF4ADE80),
                  isSelected: _selectedCategory == ActivityLogCategory.controllerRead,
                  onSelected: () => setState(() {
                    _selectedCategory = _selectedCategory == ActivityLogCategory.controllerRead
                        ? null
                        : ActivityLogCategory.controllerRead;
                  }),
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: 'Verbindung',
                  icon: Icons.lan_rounded,
                  color: const Color(0xFF60A5FA),
                  isSelected: _selectedCategory == ActivityLogCategory.connection,
                  onSelected: () => setState(() {
                    _selectedCategory = _selectedCategory == ActivityLogCategory.connection
                        ? null
                        : ActivityLogCategory.connection;
                  }),
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: 'Abrechnung',
                  icon: Icons.receipt_long_rounded,
                  color: const Color(0xFFFBBF24),
                  isSelected: _selectedCategory == ActivityLogCategory.billing,
                  onSelected: () => setState(() {
                    _selectedCategory = _selectedCategory == ActivityLogCategory.billing
                        ? null
                        : ActivityLogCategory.billing;
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    IconData? icon,
    Color? color,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    final activeColor = color ?? const Color(0xFFFFA726);
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: isSelected ? Colors.black : activeColor),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
      onSelected: (_) => onSelected(),
      backgroundColor: const Color(0xFF24242C),
      selectedColor: activeColor,
      labelStyle: TextStyle(
        color: isSelected ? Colors.black : const Color(0xFFECECF0),
      ),
      side: BorderSide(
        color: isSelected ? activeColor : const Color(0xFF3A3A44),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFF4A4A56)),
          const SizedBox(height: 12),
          const Text(
            'Keine Protokolleinträge gefunden',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFFECECF0)),
          ),
          const SizedBox(height: 4),
          Text(
            _searchQuery.isNotEmpty || _errorsOnly || _selectedCategory != null
                ? 'Versuche die Filtereinstellungen zurückzusetzen.'
                : 'Aktivitäten des Heizungsreglers und Fehlercodes werden hier live angezeigt.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF9E9EA8)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearLogs(BuildContext context, ActivityLogService logService) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF24242C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Protokolldaten löschen?'),
        content: const Text(
          'Möchtest du alle lokal gespeicherten Aktivitäten und Fehlerprotokolle unwiderruflich löschen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen', style: TextStyle(color: Color(0xFFECECF0))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF5350)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await logService.clearLogs();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Protokolldaten wurden bereinigt.')),
      );
    }
  }

  Future<void> _copyAllLogsToClipboard(BuildContext context, ECLProvider provider) async {
    final payload = provider.logService.generateDiagnosticReport(
      currentControllerId: provider.selectedControllerId,
      currentBillingId: provider.selectedBillingId,
    );
    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    await Clipboard.setData(ClipboardData(text: jsonStr));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnosebericht in Zwischenablage kopiert.')),
    );
  }

  void _showBackofficeConsentDialog(BuildContext context, ECLProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _BackofficeConsentSheet(provider: provider),
    );
  }
}

/// Expandable card representing an individual log event.
class _LogItemCard extends StatefulWidget {
  final ActivityLogEntry entry;

  const _LogItemCard({super.key, required this.entry});

  @override
  State<_LogItemCard> createState() => _LogItemCardState();
}

class _LogItemCardState extends State<_LogItemCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final color = _getColor(entry.level);
    final icon = _getIcon(entry.level, entry.category);

    final timeStr = _formatTimestamp(entry.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF24242C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: entry.level == ActivityLogLevel.error
              ? const Color(0xFFEF5350).withValues(alpha: 0.4)
              : const Color(0xFF32323C),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header Row (Level Icon, Category, Timestamp, ErrorCode) ──
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 16, color: color),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E2E38),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.category.displayName,
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFFECECF0)),
                    ),
                  ),
                  if (entry.controllerId != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2838),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        entry.controllerId!,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF60A5FA)),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    timeStr,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF7A7A85)),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 16,
                    color: const Color(0xFF7A7A85),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── Message ───────────────────────────────────────────────
              Text(
                entry.message,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFFECECF0)),
              ),

              // ── Error Code Pill (if present) ──────────────────────────
              if (entry.errorCode != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3E1F24),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFEF5350)),
                          const SizedBox(width: 4),
                          Text(
                            'Fehlercode: ${entry.errorCode}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFEF5350),
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (entry.userAcknowledged) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B3D2F),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Übermittlung bestätigt',
                          style: TextStyle(fontSize: 10, color: Color(0xFF4ADE80)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              // ── Expanded Technical Details ────────────────────────────
              if (_expanded) ...[
                const Divider(color: Color(0xFF32323C), height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Aktion: ${entry.action}',
                      style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: Color(0xFF9E9EA8)),
                    ),
                    InkWell(
                      onTap: () {
                        final jsonStr = const JsonEncoder.withIndent('  ').convert(entry.toJson());
                        Clipboard.setData(ClipboardData(text: jsonStr));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Eintrag kopiert.')),
                        );
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.copy_rounded, size: 12, color: Color(0xFFFFA726)),
                            SizedBox(width: 4),
                            Text('Kopieren', style: TextStyle(fontSize: 11, color: Color(0xFFFFA726))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (entry.details != null && entry.details!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2E2E38)),
                    ),
                    child: Text(
                      const JsonEncoder.withIndent('  ').convert(entry.details),
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Color(0xFFB0B0BC),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getColor(ActivityLogLevel level) {
    switch (level) {
      case ActivityLogLevel.error:
        return const Color(0xFFEF5350);
      case ActivityLogLevel.warning:
        return const Color(0xFFFFA726);
      case ActivityLogLevel.success:
        return const Color(0xFF4ADE80);
      case ActivityLogLevel.info:
        return const Color(0xFF60A5FA);
    }
  }

  IconData _getIcon(ActivityLogLevel level, ActivityLogCategory category) {
    if (level == ActivityLogLevel.error) return Icons.error_outline_rounded;
    if (level == ActivityLogLevel.warning) return Icons.warning_amber_rounded;

    switch (category) {
      case ActivityLogCategory.controllerWrite:
        return Icons.edit_note_rounded;
      case ActivityLogCategory.controllerRead:
        return Icons.sensors_rounded;
      case ActivityLogCategory.connection:
        return Icons.lan_rounded;
      case ActivityLogCategory.billing:
        return Icons.receipt_long_rounded;
      case ActivityLogCategory.securityGate:
        return Icons.security_rounded;
      case ActivityLogCategory.system:
        return Icons.settings_suggest_rounded;
    }
  }

  String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return '$h:$m:$s · $day.$month.';
  }
}

/// Modal bottom sheet allowing the user to review, acknowledge, and export/send
/// anonymized diagnostic reports to the backoffice.
class _BackofficeConsentSheet extends StatefulWidget {
  final ECLProvider provider;

  const _BackofficeConsentSheet({required this.provider});

  @override
  State<_BackofficeConsentSheet> createState() => _BackofficeConsentSheetState();
}

class _BackofficeConsentSheetState extends State<_BackofficeConsentSheet> {
  bool _userAcknowledged = false;
  final TextEditingController _noteController = TextEditingController();
  bool _isExporting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.provider.logService.generateDiagnosticReport(
      currentControllerId: widget.provider.selectedControllerId,
      currentBillingId: widget.provider.selectedBillingId,
      userNote: _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : null,
      anonymize: true,
    );

    final previewStr = const JsonEncoder.withIndent('  ').convert(payload);

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: ListView(
          children: [
            // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A4A56),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFA726).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.support_agent_rounded, color: Color(0xFFFFA726), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Diagnose & Fehlerbericht',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFFECECF0)),
                        ),
                        Text(
                          'Für App-Verbesserungen & Regler-Updates',
                          style: TextStyle(fontSize: 12, color: Color(0xFF9E9EA8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Explanation & Privacy notice
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF24242C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3A3A44)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.shield_outlined, size: 16, color: Color(0xFF4ADE80)),
                        SizedBox(width: 6),
                        Text(
                          'Zero-Cloud & Datenschutz',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF4ADE80)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Fehlercodes und Reglerprotokolle helfen uns, Reglerprofile zu aktualisieren '
                      'und Bugs schnell zu beheben. Alle Passwörter und Zugangsdaten werden '
                      'vollständig vor der Übertragung entfernt. Daten werden erst nach deiner '
                      'ausdrücklichen Bestätigung übermittelt.',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75), height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Optional note
              TextField(
                controller: _noteController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Optionale Beschreibung des Problems / Verhaltens',
                  labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF9E9EA8)),
                  filled: true,
                  fillColor: const Color(0xFF24242C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF3A3A44)),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Preview box
              const Text(
                'Vorschau des Diagnosepakets (JSON):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFECECF0)),
              ),
              const SizedBox(height: 6),
              Container(
                height: 180,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF141418),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2E2E38)),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    previewStr,
                    style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Color(0xFF9E9EA8)),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Acknowledgment Checkbox
              CheckboxListTile(
                value: _userAcknowledged,
                onChanged: (val) => setState(() => _userAcknowledged = val ?? false),
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFFFFA726),
                title: const Text(
                  'Ich willige in die Übermittlung des anonymisierten Fehler- und Diagnoseberichts an das Heizungstrainer-Backoffice ein.',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFECECF0)),
                ),
                subtitle: const Text(
                  'Dient ausschließlich zur Behebung von Fehlern und Weiterentwicklung der Regler-Treiber.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF7A7A85)),
                ),
              ),
              const SizedBox(height: 16),

              // Actions
              FilledButton.icon(
                icon: _isExporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: const Text('Diagnosebericht bestätigen & exportieren'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFA726),
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: (_userAcknowledged && !_isExporting)
                    ? () async {
                        setState(() => _isExporting = true);
                        try {
                          await widget.provider.logService.sendDiagnosticReport(
                            diagnosticPayload: payload,
                            userHasAcknowledged: true,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFF1B3D2F),
                              content: Text('Diagnosebericht erfolgreich bestätigt und exportiert.'),
                            ),
                          );
                        } finally {
                          if (mounted) setState(() => _isExporting = false);
                        }
                      }
                    : null,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Bericht in Zwischenablage kopieren'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFECECF0),
                  minimumSize: const Size.fromHeight(44),
                  side: const BorderSide(color: Color(0xFF3A3A44)),
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: previewStr));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Diagnose-JSON in Zwischenablage kopiert.')),
                  );
                },
              ),
            ],
          ),
        ),
      );
  }
}
