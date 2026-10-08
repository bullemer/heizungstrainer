import 'package:heizungstrainer/utils/number_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/exceptions/license_exception.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/ecl_reading.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/config_check_screen.dart';
import 'package:heizungstrainer/screens/curve_simulator_screen.dart';
import 'package:heizungstrainer/screens/dhw_settings_screen.dart';
import 'package:heizungstrainer/screens/live_view_screen.dart';
import 'package:heizungstrainer/screens/settings_screen.dart';
import 'package:heizungstrainer/services/heating_analytics_service.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';
import 'package:heizungstrainer/widgets/analysis_section.dart';
import 'package:heizungstrainer/widgets/building_profile_picker.dart';
import 'package:heizungstrainer/widgets/controller_schedule_card.dart';
import 'package:heizungstrainer/widgets/holiday_end_flow.dart';
import 'package:heizungstrainer/widgets/pro_upgrade_dialog.dart';
import 'package:heizungstrainer/widgets/sparkline_chart.dart';
import 'package:heizungstrainer/widgets/radial_indicator.dart';

/// Primary "Mein Zuhause" dashboard — consumer-grade heating control.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static ControllerHeatingCurve? _controllerCurve(ECLProvider provider) =>
      ControllerHeatingCurve.fromReadings(provider.getReading);

  /// Lets the user enter/correct the annual heating consumption used for the
  /// savings estimate (overrides the billing portal value).
  static Future<void> _editAnnualKwh(BuildContext context, ECLProvider provider) async {
    final controller = TextEditingController(
      text: provider.annualHeatingKwhManual?.fixed(0) ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Heizenergie pro Jahr'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            suffixText: 'kWh',
            hintText: provider.annualHeatingKwh?.fixed(0),
            helperText: 'Steht auf deiner Heizkostenabrechnung. Leer lassen = Wert aus der Abrechnung.',
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Speichern')),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    await provider.setAnnualHeatingKwh(
      double.tryParse(result.trim().replaceAll('.', '').replaceAll(',', '.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mein Zuhause',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        actions: [
          Consumer<ECLProvider>(
            builder: (context, provider, _) {
              final isPro = provider.licenseService.isPro;
              return IconButton(
                onPressed: () => ProUpgradeDialog.show(context),
                icon: Icon(
                  isPro ? Icons.workspace_premium_rounded : Icons.workspace_premium_outlined,
                  color: isPro ? const Color(0xFF66BB6A) : const Color(0xFFFFA726),
                  size: 22,
                ),
                tooltip: provider.licenseService.isEarlyAdopter
                    ? 'Early Adopter – alle Funktionen frei'
                    : isPro
                        ? 'Pro-Lizenz aktiv'
                        : 'Upgrade auf Pro',
              );
            },
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings_outlined, size: 22),
            tooltip: 'Einstellungen',
          ),
          Consumer<ECLProvider>(
            builder: (_, p, child) => IconButton(
              onPressed: p.refreshReadings,
              icon: const Icon(Icons.refresh_rounded, size: 22),
              tooltip: 'Aktualisieren',
            ),
          ),
          Consumer<ECLProvider>(
            builder: (_, p, child) => PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'disconnect') {
                  p.disconnect();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'ip',
                  enabled: false,
                  child: Row(
                    children: [
                      const Icon(Icons.router_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(p.controllerIp ?? '—'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'disconnect',
                  child: Row(
                    children: [
                      Icon(Icons.logout_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Trennen'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Consumer<ECLProvider>(
        builder: (context, provider, _) {
          return RefreshIndicator(
            onRefresh: provider.refreshReadings,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                if (provider.isReconnecting) ...[
                  const _ReconnectingBanner(),
                  const SizedBox(height: 12),
                ] else if (!provider.isConnected) ...[
                  _OfflineModeBanner(provider: provider),
                  const SizedBox(height: 12),
                ],
                if (provider.isSimulatedController) ...[
                  _SimulatedControllerBanner(provider: provider),
                  const SizedBox(height: 12),
                ],
                // ── Aktiver Urlaubsmodus (nur wenn aktiv) ───
                ActiveHolidayCard(provider: provider),

                // ── Gebäude ─────────────────────────────────
                BuildingProfileCard(provider: provider),
                const SizedBox(height: 12),

                // ── Smart Status Banner ─────────────────────
                _SmartStatusBanner(provider: provider),
                const SizedBox(height: 18),

                // ── Heizung ─────────────────────────────────
                _SectionLabel(label: 'Heizung'),
                const SizedBox(height: 10),
                if (provider.supportsControllerSchedule) ...[
                  ConfigCheckCard(provider: provider),
                  const SizedBox(height: 12),
                ],
                if (provider.supportsLiveView) ...[
                  _LiveViewTile(),
                  const SizedBox(height: 12),
                ],
                _HeatingComfortCard(provider: provider),
                if (provider.controllerSchedule != null) ...[
                  const SizedBox(height: 12),
                  ControllerScheduleCard(provider: provider),
                ],
                if (_controllerCurve(provider) != null &&
                    provider.getReading(ECLRegisters.roomTargetTemp) != null) ...[
                  const SizedBox(height: 12),
                  HeatingSimulationCard(
                    curve: _controllerCurve(provider)!,
                    roomSetpoint: provider.getReading(ECLRegisters.roomTargetTemp)!.displayValue,
                    previewSetpoint: provider.comfortPreview,
                    outdoorTemp: provider.getReading(ECLRegisters.outdoorTemp)?.displayValue ?? 0,
                    annualHeatingKwh: provider.annualHeatingKwh,
                    annualHeatingKwhSource: provider.annualHeatingKwhSource,
                    pricePerKwh: provider.pricePerKwhCached,
                    onEditAnnualKwh: () => _editAnnualKwh(context, provider),
                    buildingReference: provider.buildingReference,
                    onPickBuildingReference: () => showBuildingProfilePicker(context, provider),
                    onOpenAssistant: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CurveSimulatorScreen()),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.local_fire_department_rounded,
                        label: 'Heizwasser Zufluss',
                        parameter: ECLRegisters.flowTemp,
                        history: provider.getHistory(ECLRegisters.flowTemp),
                        reading: provider.getReading(ECLRegisters.flowTemp),
                        accentColor: const Color(0xFFFF7043),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.water_drop_outlined,
                        label: 'Heizwasser Rückfluss',
                        parameter: ECLRegisters.returnTemp,
                        history: provider.getHistory(ECLRegisters.returnTemp),
                        reading: provider.getReading(ECLRegisters.returnTemp),
                        accentColor: const Color(0xFF66BB6A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _EfficiencyDeltaChip(provider: provider),
                const SizedBox(height: 24),

                // ── Warmwasser ──────────────────────────────
                _SectionLabel(label: 'Warmwasser'),
                const SizedBox(height: 10),
                GestureDetector(
                  key: const Key('openDhwSettings'),
                  onTap: provider.supportsDhwSettings
                      ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DhwSettingsScreen()))
                      : null,
                  child: _HotWaterCard(provider: provider),
                ),
                const SizedBox(height: 24),

                // ── Abrechnung & Analyse ────────────────────
                AnalysisSection(
                  currentOutdoorTemp:
                      provider.getReading(ECLRegisters.outdoorTemp)?.displayValue ?? 0,
                  currentFlowTemp:
                      provider.getReading(ECLRegisters.flowTemp)?.displayValue ?? 0,
                  currentReturnTemp:
                      provider.getReading(ECLRegisters.returnTemp)?.displayValue ?? 0,
                  parallelShift:
                      provider.getReading(ECLRegisters.heatingCurveShift)?.displayValue ?? 0,
                  brunataData: provider.brunataData,
                  brunataSyncState: provider.brunataSyncState,
                  brunataSyncError: provider.brunataSyncError,
                  onSyncBrunata: provider.syncBrunataData,
                  lastBillingSyncTime: provider.lastBillingSyncTime,
                  billingProviderName:
                      provider.currentBillingDescriptor.name,
                  // The real curve is shown in the heating area above.
                  showHeatingCurve: _controllerCurve(provider) == null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Reconnecting Banner
// ═══════════════════════════════════════════════════════════════════════════

class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFA726).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFA726).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFFFA726),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Verbindung kurz unterbrochen – erneuter Versuch läuft…',
              style: TextStyle(
                color: const Color(0xFFFFA726).withValues(alpha: 0.95),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineModeBanner extends StatelessWidget {
  final ECLProvider provider;
  const _OfflineModeBanner({required this.provider});

  @override
  Widget build(BuildContext context) {
    final lastPoll = provider.lastSuccessfulPoll;
    final timeStr = lastPoll != null
        ? '${lastPoll.hour.toString().padLeft(2, '0')}:${lastPoll.minute.toString().padLeft(2, '0')} Uhr'
        : 'aus Speicher';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF7C4DFF).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF7C4DFF).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.offline_bolt_rounded,
              color: Color(0xFFB388FF), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Offline-Ansicht ($timeStr) · Nur Leseansicht',
              style: const TextStyle(
                color: Color(0xFFB388FF),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () {
              provider.exitOfflineMode();
              provider.connectToController();
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(50, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Verbinden',
              style: TextStyle(
                color: Color(0xFFB388FF),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          // No controller at hand (or Play review): try everything simulated.
          TextButton(
            key: const ValueKey('home_start_demo'),
            onPressed: () => provider.startSimulation(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(50, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Demo',
              style: TextStyle(
                color: Color(0xFFB388FF),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimulatedControllerBanner extends StatelessWidget {
  final ECLProvider provider;
  const _SimulatedControllerBanner({required this.provider});

  @override
  Widget build(BuildContext context) {
    final desc = provider.currentControllerDescriptor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFA726).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFA726).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(desc.icon, color: const Color(0xFFFFA726), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Simulation: ${desc.brand} ${desc.model}',
              style: const TextStyle(
                color: Color(0xFFFFA726),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(50, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: const Color(0xFFFFA726),
            ),
            child: const Text('Wechseln', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Smart Status Banner
// ═══════════════════════════════════════════════════════════════════════════

class _SmartStatusBanner extends StatelessWidget {
  final ECLProvider provider;
  const _SmartStatusBanner({required this.provider});

  @override
  Widget build(BuildContext context) {
    final outdoorReading = provider.getReading(ECLRegisters.outdoorTemp);
    final shiftReading = provider.getReading(ECLRegisters.heatingCurveShift);
    final isSensorDisconnected =
        outdoorReading == null || outdoorReading.isSensorDisconnected;
    final outdoorTemp = isSensorDisconnected ? 0.0 : outdoorReading.displayValue;
    final shift = shiftReading?.displayValue ?? 0;

    // The controller's own "Sommer-Aus" if it reports one (e.g. 13 °C);
    // 17 °C is only a fallback for controllers that don't.
    final summerCutoff =
        provider.getReading(ECLRegisters.summerCutoff)?.displayValue ?? 17.0;
    final isSummerMode = !isSensorDisconnected && outdoorTemp > summerCutoff;
    final isHighConsumption = shift > 3;

    final bannerColor = isSensorDisconnected
        ? const Color(0xFFEF5350).withValues(alpha: 0.15)
        : (isSummerMode
            ? const Color(0xFF1B5E20).withValues(alpha: 0.35)
            : const Color(0xFF2A2A32));
    final borderColor = isSensorDisconnected
        ? const Color(0xFFEF5350).withValues(alpha: 0.35)
        : (isSummerMode
            ? const Color(0xFF66BB6A).withValues(alpha: 0.4)
            : const Color(0xFF3A3A44));
    final iconColor = isSensorDisconnected
        ? const Color(0xFFEF5350)
        : (isSummerMode ? const Color(0xFF66BB6A) : const Color(0xFFFFA726));

    final title = isSensorDisconnected
        ? 'Außentemperaturfühler nicht verbunden'
        : (isSummerMode
            ? '${outdoorTemp.fixed(1)}°C draußen — über der Heizgrenze (${summerCutoff.fixed(0)} °C)'
            : '${outdoorTemp.fixed(1)}°C draußen — Heizbetrieb aktiv');

    final subtitle = isSensorDisconnected
        ? 'Der ECL-Regler meldet einen Fühlerabriss (S1). Bitte Fühlerverkabelung prüfen.'
        : (isSummerMode
            ? 'Der Regler heizt oberhalb seiner Heizgrenze nicht (Sommer-Aus).'
            : 'Die Heizung reguliert aktiv deine Raumtemperatur.');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSensorDisconnected
                    ? Icons.sensors_off_rounded
                    : (isSummerMode ? Icons.wb_sunny_rounded : Icons.thermostat),
                color: iconColor,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: iconColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12.5,
            ),
          ),
          // Warning chip for high consumption
          if (isHighConsumption) ...[
            const SizedBox(height: 12),
            _HighConsumptionWarning(provider: provider, shiftValue: shift),
          ],
        ],
      ),
    );
  }
}

class _HighConsumptionWarning extends StatelessWidget {
  final ECLProvider provider;
  final double shiftValue;
  const _HighConsumptionWarning({
    required this.provider,
    required this.shiftValue,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          HapticFeedback.mediumImpact();
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Heizkurve zurücksetzen?'),
              content: Text(
                'Die Heizkurve steht aktuell auf '
                '${shiftValue > 0 ? '+' : ''}${shiftValue.fixed(0)}. '
                'Möchtest du sie auf 0 (Neutral) zurücksetzen, '
                'um den Verbrauch zu optimieren?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Zurücksetzen'),
                ),
              ],
            ),
          );
          if (confirmed == true && context.mounted) {
            try {
              await provider.writeParameter(ECLRegisters.heatingCurveShift, 0);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('✅ Heizkurve auf Neutral zurückgesetzt'),
                  backgroundColor: Color(0xFF66BB6A),
                ));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(userFacingError(e, fallback: 'Fehler beim Zurücksetzen')),
                  backgroundColor: const Color(0xFFEF5350),
                ));
              }
            }
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFA726).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFFFA726).withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFFFA726), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Erhöhter Verbrauch! Tippe zum Optimieren.',
                  style: TextStyle(
                    color: const Color(0xFFFFA726).withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFFFFA726), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Zone 1: Heating Comfort Slider
// ═══════════════════════════════════════════════════════════════════════════

class _HeatingComfortCard extends StatefulWidget {
  final ECLProvider provider;
  const _HeatingComfortCard({required this.provider});

  @override
  State<_HeatingComfortCard> createState() => _HeatingComfortCardState();
}

class _HeatingComfortCardState extends State<_HeatingComfortCard> {
  late double _sliderValue;
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _syncFromProvider();
  }

  // Room-setpoint mode: some controllers (e.g. Danfoss ECL 310 applications
  // without a "Verschieben" parameter) move the heating curve via the comfort
  // room setpoint instead of a shift.
  static const double _roomMin = 17;
  static const double _roomMax = 25;

  ECLReading? get _shiftReading =>
      widget.provider.getReading(ECLRegisters.heatingCurveShift);
  ECLReading? get _roomReading =>
      widget.provider.getReading(ECLRegisters.roomTargetTemp);

  bool get _roomMode => _shiftReading == null && _roomReading != null;
  bool get _hasControl => _shiftReading != null || _roomReading != null;

  ECLParameter get _parameter =>
      _roomMode ? ECLRegisters.roomTargetTemp : ECLRegisters.heatingCurveShift;

  /// Slider position on the -3..+3 comfort scale (for colours/energy text).
  double get _comfortOffset => _roomMode
      ? (_sliderValue - (_roomReading?.displayValue ?? 21)).clamp(-3, 3).toDouble()
      : _sliderValue;

  void _syncFromProvider() {
    if (_roomMode) {
      final room = _roomReading!.displayValue.clamp(_roomMin, _roomMax).toDouble();
      _sliderValue = (room * 2).round() / 2;
    } else {
      _sliderValue = (_shiftReading?.displayValue ?? 0).clamp(-3, 3).toDouble();
    }
  }

  @override
  void didUpdateWidget(covariant _HeatingComfortCard old) {
    super.didUpdateWidget(old);
    if (!_isEditing) _syncFromProvider();
  }

  String _comfortLabel(double value) {
    if (_roomMode) return '${value.fixed(1)} °C';
    if (value <= -3) return 'Sparmodus';
    if (value <= -2) return 'Etwas kühler';
    if (value <= -1) return 'Leicht reduziert';
    if (value == 0) return 'Neutral';
    if (value <= 1) return 'Leicht erhöht';
    if (value <= 2) return 'Etwas wärmer';
    return 'Max. Komfort';
  }

  Color _comfortColor(double value) {
    if (value <= -2) return const Color(0xFF42A5F5);
    if (value <= -1) return const Color(0xFF66BB6A);
    if (value <= 1) return const Color(0xFF8BC34A);
    if (value <= 2) return const Color(0xFFFFA726);
    return const Color(0xFFFF7043);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();
    try {
      await widget.provider.writeParameter(_parameter, _sliderValue);
      widget.provider.setComfortPreview(null);
      if (mounted) {
        setState(() {
          _isEditing = false;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_roomMode
              ? 'Komfort-Raumsollwert auf ${_comfortLabel(_sliderValue)} gesetzt'
              : 'Heizkurve auf ${_comfortLabel(_sliderValue)} gesetzt'),
          backgroundColor: const Color(0xFF66BB6A),
        ));
      }
    } on LicenseRequiredException {
      if (mounted) {
        setState(() => _isSaving = false);
        await ProUpgradeDialog.show(
          context,
          featureHint: 'Das Verstellen und Schreiben der Heizkurve',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(userFacingError(e, fallback: 'Fehler beim Speichern')),
          backgroundColor: const Color(0xFFEF5350),
        ));
      }
    }
  }

  Widget _buildRoomModePreview(Color accent) {
    final current = _roomReading?.displayValue;
    final curve = ControllerHeatingCurve.fromReadings(widget.provider.getReading);
    final outdoor = widget.provider.getReading(ECLRegisters.outdoorTemp);
    final outdoorTemp =
        (outdoor != null && !outdoor.isSensorDisconnected) ? outdoor.displayValue : null;
    if (current == null || (_sliderValue - current).abs() < 0.25) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'Aktueller Komfort-Raumsollwert des Reglers. Schieb den Regler, um zu sehen, '
          'wie sich Heizkurve, Energie und Kosten ändern.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5, height: 1.35),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (curve != null && outdoorTemp != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Vorlauf bei ${outdoorTemp.fixed(1)} °C außen: '
                '${curve.flowAt(outdoorTemp, current).fixed(1)} → '
                '${curve.flowAt(outdoorTemp, _sliderValue).fixed(1)} °C '
                '(Kurve unten gestrichelt)',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5),
              ),
            ),
          Text(
            'Ersparnis in Energie und € siehe „Heizkurve & Sparpotenzial“ direkt darunter.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildPhysicalImpactPreview(double sliderValue, Color accent) {
    if (_roomMode) return _buildRoomModePreview(accent);
    final outdoorReading = widget.provider.getReading(ECLRegisters.outdoorTemp);
    final outdoorTemp =
        (outdoorReading != null && !outdoorReading.isSensorDisconnected)
            ? outdoorReading.displayValue
            : 0.0;

    final currentReading =
        widget.provider.getReading(ECLRegisters.heatingCurveShift);
    final activeShift = currentReading?.displayValue ?? 0.0;

    final flowTargetCurrent = HeatingAnalyticsService.calculateFlowTarget(
      outdoorTemp,
      parallelShift: activeShift,
    );
    final flowTargetSelected = HeatingAnalyticsService.calculateFlowTarget(
      outdoorTemp,
      parallelShift: sliderValue,
    );
    final flowDelta = flowTargetSelected - flowTargetCurrent;

    // ~6 % per °C room temperature. A flow-temperature shift changes the room
    // temperature less (EnergieSchweiz: radiators 5 K flow ≈ 2.5 K room, floor
    // heating 2 K ≈ 2 K) – assuming the shift step is 1 K of flow temperature.
    final roomPerFlowK = widget.provider.isFloorHeating ? 1.0 : 0.5;
    final percentEnergy = (sliderValue * roomPerFlowK * 6.0).round();
    final isOffline = !widget.provider.isConnected;

    final String energyText;
    final String flowText;
    final IconData icon;
    final Color color;

    if (sliderValue < 0) {
      energyText = 'ca. ${(-percentEnergy)}% weniger Heizenergie';
      flowText =
          'Vorlauf sinkt bei ${outdoorTemp.fixed(0)} °C Außentemp auf ${flowTargetSelected.fixed(1)} °C (${flowDelta.fixed(1)} °C)';
      icon = Icons.eco_rounded;
      color = const Color(0xFF66BB6A);
    } else if (sliderValue == 0) {
      energyText = 'Norm-Auslegung (Ausgangsbasis)';
      flowText =
          'Vorlauf-Sollwert: ${flowTargetSelected.fixed(1)} °C (bei ${outdoorTemp.fixed(0)} °C Außentemperatur)';
      icon = Icons.check_circle_outline_rounded;
      color = const Color(0xFF8BC34A);
    } else {
      energyText = 'ca. +$percentEnergy% höherer Energieaufwand';
      flowText =
          'Vorlauf steigt bei ${outdoorTemp.fixed(0)} °C Außentemp auf ${flowTargetSelected.fixed(1)} °C (+${flowDelta.fixed(1)} °C)';
      icon = Icons.local_fire_department_rounded;
      color = const Color(0xFFFF7043);
    }

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  energyText,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isOffline)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Offline: Schreibschutz',
                    style: TextStyle(color: Color(0xFF9E9EA8), fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            flowText,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _comfortColor(_comfortOffset);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isEditing
              ? accent.withValues(alpha: 0.5)
              : const Color(0xFF3A3A44),
          width: _isEditing ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: accent.withValues(alpha: 0.12),
                ),
                child: Icon(Icons.thermostat_rounded, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Haus Basis-Wärme',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Color(0xFFECECF0),
                      ),
                    ),
                    Text(
                      _roomMode ? 'Komfort-Raumsollwert (verschiebt die Heizkurve)' : 'Heizkurve',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              // Current value badge
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _comfortLabel(_sliderValue),
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Slider
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accent,
              inactiveTrackColor: accent.withValues(alpha: 0.15),
              thumbColor: accent,
              overlayColor: accent.withValues(alpha: 0.12),
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
            ),
            child: Slider(
              value: _sliderValue.clamp(_roomMode ? _roomMin : -3, _roomMode ? _roomMax : 3).toDouble(),
              min: _roomMode ? _roomMin : -3,
              max: _roomMode ? _roomMax : 3,
              divisions: _roomMode ? ((_roomMax - _roomMin) * 2).round() : 6,
              onChanged: widget.provider.isConnected && _hasControl
                  ? (v) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _sliderValue = v;
                        _isEditing = true;
                      });
                      if (_roomMode) widget.provider.setComfortPreview(v);
                    }
                  : null,
            ),
          ),

          if (widget.provider.isConnected && !_hasControl)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Dieser Regler stellt weder eine Parallelverschiebung noch einen '
                'Raum-Sollwert zum Verstellen bereit.',
                style: TextStyle(fontSize: 11.5, color: Colors.orange.shade200),
              ),
            ),

          if (widget.provider.isConnected && widget.provider.isBetaWriteBlocked)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Beta-Regler: nur Lesen. Schreibzugriff in den Einstellungen freigeben.',
                style: TextStyle(fontSize: 11.5, color: Colors.orange.shade200),
              ),
            ),

          // Scale labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _roomMode ? '❄️ ${_roomMin.fixed(0)} °C' : '❄️ Sparmodus',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                Text(
                  _roomMode ? '🔥 ${_roomMax.fixed(0)} °C' : '🔥 Max. Komfort',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),

          // Live physical impact preview
          _buildPhysicalImpactPreview(_sliderValue, accent),

          // Save/Cancel buttons
          if (_isEditing) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () {
                            setState(() {
                              _isEditing = false;
                              _syncFromProvider();
                            });
                            widget.provider.setComfortPreview(null);
                          },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Text('Abbrechen'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_isSaving ? 'Sende…' : 'Übernehmen'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Zone 2: Hot Water Card
// ═══════════════════════════════════════════════════════════════════════════

class _HotWaterCard extends StatelessWidget {
  final ECLProvider provider;
  const _HotWaterCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final reading = provider.getReading(ECLRegisters.hotWaterTemp);
    final isDisconnected = reading == null || reading.isSensorDisconnected;
    final temp = isDisconnected ? 0.0 : reading.displayValue;
    final isReady = !isDisconnected && temp >= 50.0;
    final accent = isDisconnected
        ? const Color(0xFF9E9EA8)
        : (isReady ? const Color(0xFF42A5F5) : const Color(0xFFFFA726));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A44)),
      ),
      child: Row(
        children: [
          // Radial indicator
          RadialTemperatureIndicator(
            currentTemp: temp,
            targetTemp: provider.getReading(ECLRegisters.dhwComfortSetpoint)?.displayValue ?? 55.0,
            size: 100,
            accentColor: accent,
            isDisconnected: isDisconnected,
          ),
          const SizedBox(width: 20),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.water_drop_rounded,
                      color: accent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Dusch- & Trinkwarmwasser',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Color(0xFFECECF0),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Status label
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isDisconnected ? '⚠️' : (isReady ? '💧' : '⏳'),
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          isDisconnected
                              ? 'Fühler nicht verbunden'
                              : (isReady
                                  ? 'Heiß & Bereit'
                                  : 'Wird nachgeheizt...'),
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final extra in [ECLRegisters.dhwTankBottom, ECLRegisters.dhwChargeFlow])
                  if (provider.getReading(extra) case final r? when !r.isSensorDisconnected)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${extra.id == ECLRegisters.dhwTankBottom.id ? 'Speicher unten (S8)' : 'Ladevorlauf (S4)'}: '
                        '${r.displayValue.fixed(1)} °C',
                        key: Key('dhw_${extra.id}'),
                        style: const TextStyle(fontSize: 12, color: Color(0xFFBDBDC7)),
                      ),
                    ),
                if (provider.supportsDhwSettings)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Einstellungen ›', style: TextStyle(fontSize: 12, color: Color(0xFF42A5F5), fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 8),
                Text(
                  isDisconnected
                      ? 'Kein Fühlersignal (S6)'
                      : 'Zieltemperatur: ${(provider.getReading(ECLRegisters.dhwComfortSetpoint)?.displayValue ?? 55.0).fixed(1)} °C',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Metric Card (Vorlauf / Rücklauf)
// ═══════════════════════════════════════════════════════════════════════════

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final ECLParameter parameter;
  final List<double> history;
  final ECLReading? reading;
  final Color accentColor;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.parameter,
    required this.history,
    required this.reading,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDisconnected = reading == null || reading!.isSensorDisconnected;
    final temp = isDisconnected ? 0.0 : reading!.displayValue;
    final effectiveColor =
        isDisconnected ? const Color(0xFF9E9EA8) : accentColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + label
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: effectiveColor.withValues(alpha: 0.12),
                ),
                child: Icon(icon, color: effectiveColor, size: 17),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Temperature
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isDisconnected ? '—' : temp.fixed(1),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: isDisconnected
                      ? const Color(0xFF9E9EA8)
                      : const Color(0xFFECECF0),
                ),
              ),
              if (!isDisconnected)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    '°C',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF9E9EA8),
                    ),
                  ),
                ),
            ],
          ),
          // Sparkline
          if (!isDisconnected && history.length >= 2) ...[
            const SizedBox(height: 10),
            SparklineChart(
              data: history,
              lineColor: accentColor,
              height: 32,
              strokeWidth: 1.5,
            ),
          ],
          // Heat bar
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 4,
              child: LinearProgressIndicator(
                value: isDisconnected ? 0.0 : (temp / 80.0).clamp(0.0, 1.0),
                backgroundColor: effectiveColor.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(effectiveColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Efficiency Delta Chip
// ═══════════════════════════════════════════════════════════════════════════

class _EfficiencyDeltaChip extends StatelessWidget {
  final ECLProvider provider;
  const _EfficiencyDeltaChip({required this.provider});

  @override
  Widget build(BuildContext context) {
    final flowReading = provider.getReading(ECLRegisters.flowTemp);
    final returnReading = provider.getReading(ECLRegisters.returnTemp);

    final hasValidSensors = flowReading != null &&
        !flowReading.isSensorDisconnected &&
        returnReading != null &&
        !returnReading.isSensorDisconnected;

    if (!hasValidSensors) {
      return const SizedBox.shrink();
    }

    final flow = flowReading.displayValue;
    final ret = returnReading.displayValue;
    final delta = flow - ret;
    final isHealthy = delta >= 5 && delta <= 25;
    final color =
        isHealthy ? const Color(0xFF66BB6A) : const Color(0xFFFFA726);

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isHealthy
                  ? Icons.check_circle_outline_rounded
                  : Icons.info_outline_rounded,
              color: color,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              'Effizienz-Delta: ${delta.fixed(1)}°C',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section Label
// ═══════════════════════════════════════════════════════════════════════════

/// Opens the live plant diagram.
class _LiveViewTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF2A2A32),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const Key('openLiveView'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveViewScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF3A3A44)),
            ),
            child: const Row(children: [
              Icon(Icons.account_tree_outlined, color: Color(0xFFFFA726), size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Anlage live',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFFECECF0))),
                  SizedBox(height: 2),
                  Text('Anlagenbild mit Ist- und Sollwerten, Pumpen und Ventilen',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF9E9EA8))),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: Color(0xFF9E9EA8)),
            ]),
          ),
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.5),
        letterSpacing: 0.5,
      ),
    );
  }
}
