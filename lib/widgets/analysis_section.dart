/// Analysis & savings potential section for the dashboard.
///
/// Combines Brunata cost data, the interactive heating curve chart,
/// and the smart intelligence engine into a unified card.
library;

import 'package:flutter/material.dart';

import 'package:heizungstrainer/models/brunata_meter_data.dart';
import 'package:heizungstrainer/screens/brunata_detail_screen.dart';
import 'package:heizungstrainer/services/brunata_local_scraper_service.dart';
import 'package:heizungstrainer/services/heating_analytics_service.dart';
import 'package:heizungstrainer/widgets/app_top_status_bar.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';
import 'package:heizungstrainer/widgets/controller_curve_chart.dart';
import 'package:heizungstrainer/widgets/heating_curve_chart.dart';

/// The full "Analyse & Sparpotenzial" section.
///
/// Accepts live sensor data and renders:
/// 1. Brunata cost summary with community comparison
/// 2. Interactive heating curve line chart
/// 3. Smart savings advice engine
class AnalysisSection extends StatelessWidget {
  final double currentOutdoorTemp;
  final double currentFlowTemp;
  final double currentReturnTemp;
  final double parallelShift;
  final BrunataMeterData? brunataData;
  final BrunataSyncState brunataSyncState;
  final String? brunataSyncError;
  final VoidCallback? onSyncBrunata;
  final DateTime? lastBillingSyncTime;
  final String? billingProviderName;

  /// The controller's real curve (Danfoss), with the current comfort
  /// setpoint and the setpoint being previewed on the home slider. When
  /// present, these replace the generic model curve and savings tip.
  final ControllerHeatingCurve? controllerCurve;
  final double? roomSetpoint;
  final double? previewSetpoint;
  final double? annualHeatingKwh;
  final String? annualHeatingKwhSource;
  final double? pricePerKwh;

  /// False when the screen shows the heating curve elsewhere.
  final bool showHeatingCurve;

  const AnalysisSection({
    super.key,
    required this.currentOutdoorTemp,
    required this.currentFlowTemp,
    required this.currentReturnTemp,
    required this.parallelShift,
    this.brunataData,
    this.brunataSyncState = BrunataSyncState.idle,
    this.brunataSyncError,
    this.onSyncBrunata,
    this.lastBillingSyncTime,
    this.billingProviderName,
    this.controllerCurve,
    this.roomSetpoint,
    this.previewSetpoint,
    this.annualHeatingKwh,
    this.annualHeatingKwhSource,
    this.pricePerKwh,
    this.showHeatingCurve = true,
  });

  @override
  Widget build(BuildContext context) {
    final brunata = brunataData;
    final savings = HeatingAnalyticsService.analyzeSavings(
      currentShift: parallelShift,
      // Use the real synced heating cost; 0 falls back to an estimate.
      annualBaseCost: brunata?.currentBillingPeriodCost ?? 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section Header ──────────────────────────────────
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.12),
              ),
              child: const Icon(
                Icons.analytics_outlined,
                color: Color(0xFF7C4DFF),
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Analyse & Sparpotenzial',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9E9EA8),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── A. Brunata Cost Card (tap to drill down) ────────
        GestureDetector(
          onTap: (brunata != null &&
                  brunata.hasDetail &&
                  brunataSyncState != BrunataSyncState.initializing &&
                  brunataSyncState != BrunataSyncState.loggingIn &&
                  brunataSyncState != BrunataSyncState.navigating &&
                  brunataSyncState != BrunataSyncState.scraping)
              ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BrunataDetailScreen(data: brunata),
                    ),
                  )
              : null,
          child: _BrunataCostCard(
            brunata: brunata,
            syncState: brunataSyncState,
            syncError: brunataSyncError,
            onSync: onSyncBrunata,
            showDetailHint: brunata?.hasDetail ?? false,
            lastBillingSyncTime: lastBillingSyncTime,
            billingProviderName: billingProviderName,
          ),
        ),
        const SizedBox(height: 12),

        // ── B. Heating Curve Chart ──────────────────────────
        if (!showHeatingCurve)
          const SizedBox.shrink()
        else if (controllerCurve != null && roomSetpoint != null)
          HeatingSimulationCard(
            curve: controllerCurve!,
            roomSetpoint: roomSetpoint!,
            previewSetpoint: previewSetpoint,
            outdoorTemp: currentOutdoorTemp,
            annualHeatingKwh: annualHeatingKwh,
            annualHeatingKwhSource: annualHeatingKwhSource,
            pricePerKwh: pricePerKwh,
          )
        else ...[
          _HeatingCurveSection(
            parallelShift: parallelShift,
            currentOutdoorTemp: currentOutdoorTemp,
            currentFlowTemp: currentFlowTemp,
          ),
          const SizedBox(height: 12),

          // ── C. Smart Savings Advice (generic model) ───────
          if (savings.hasOptimizationPotential)
            _SavingsAdviceCard(savings: savings),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// A. Brunata Cost Card
// ═══════════════════════════════════════════════════════════════════════════

class _BrunataCostCard extends StatelessWidget {
  final BrunataMeterData? brunata;
  final BrunataSyncState syncState;
  final String? syncError;
  final VoidCallback? onSync;
  final bool showDetailHint;
  final DateTime? lastBillingSyncTime;
  final String? billingProviderName;

  const _BrunataCostCard({
    required this.brunata,
    this.syncState = BrunataSyncState.idle,
    this.syncError,
    this.onSync,
    this.showDetailHint = false,
    this.lastBillingSyncTime,
    this.billingProviderName,
  });

  String get _effectiveBillingName =>
      billingProviderName ?? 'Abrechnungsstelle';

  bool get _isSyncing =>
      syncState != BrunataSyncState.idle &&
      syncState != BrunataSyncState.complete &&
      syncState != BrunataSyncState.error;

  String get _syncLabel {
    switch (syncState) {
      case BrunataSyncState.initializing:
        return 'Browser wird gestartet…';
      case BrunataSyncState.loggingIn:
        return 'Anmeldung bei Brunata…';
      case BrunataSyncState.navigating:
        return 'Portal wird geladen…';
      case BrunataSyncState.scraping:
        return 'Daten werden gelesen…';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final meterData = brunata;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.euro_rounded,
                  color: Color(0xFFFFA726), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Heizkosten dieses Jahr',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: Color(0xFFECECF0),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastBillingSyncTime != null
                          ? '$_effectiveBillingName · Letzter Sync: ${AppTopStatusBar.formatSyncTime(lastBillingSyncTime!)}'
                          : '$_effectiveBillingName · Noch nie synchronisiert',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: lastBillingSyncTime != null
                            ? const Color(0xFF9E9EA8)
                            : const Color(0xFFFFB74D),
                      ),
                    ),
                  ],
                ),
              ),
              if (showDetailHint) ...[
                Text(
                  'Details',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFFA726).withValues(alpha: 0.9),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFFFFA726), size: 18),
                const SizedBox(width: 4),
              ],
              if (meterData != null &&
                  meterData.communityComparisonPercentage.abs() >= 0.5)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (meterData.isAboveCommunityAverage
                            ? const Color(0xFFFFA726)
                            : const Color(0xFF66BB6A))
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (meterData.isAboveCommunityAverage
                              ? const Color(0xFFFFA726)
                              : const Color(0xFF66BB6A))
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    meterData.isAboveCommunityAverage
                        ? '⚠️ ${meterData.communityComparisonPercentage.toStringAsFixed(0)}% über Schnitt'
                        : '🌱 ${meterData.communityComparisonPercentage.abs().toStringAsFixed(0)}% unter Schnitt',
                    style: TextStyle(
                      color: meterData.isAboveCommunityAverage
                          ? const Color(0xFFFFA726)
                          : const Color(0xFF66BB6A),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Sync loading overlay
          if (_isSyncing)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFFFA726),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(_syncLabel, style: TextStyle(
                    fontSize: 13, color: Colors.white.withValues(alpha: 0.7),
                  )),
                ],
              ),
            )
          else ...[
            // Cost & consumption
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meterData != null
                            ? '${meterData.currentBillingPeriodCost.toStringAsFixed(2)} €'
                            : '– €',
                        style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold,
                          color: Color(0xFFECECF0),
                        ),
                      ),
                      Text(
                        meterData != null
                            ? 'Heizkosten bisher (geschätzt)'
                            : 'Noch nicht synchronisiert',
                        style: TextStyle(
                          fontSize: 11.5, color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 40, color: const Color(0xFF3A3A44)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meterData != null
                            ? '${meterData.consumedKwh.toStringAsFixed(0)} kWh'
                            : '– kWh',
                        style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold,
                          color: Color(0xFF9E9EA8),
                        ),
                      ),
                      Text(
                        meterData != null
                            ? 'Heizung Ist-Verbrauch'
                            : 'Keine Messwerte vorhanden',
                        style: TextStyle(
                          fontSize: 11.5, color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              meterData != null
                  ? '${(meterData.costPerKwh * 100).toStringAsFixed(1)} ct/kWh'
                  : 'Tarif wird nach Synchronisation berechnet',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.35)),
            ),
          ],
          // Error
          if (syncState == BrunataSyncState.error && syncError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF5350).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Color(0xFFEF5350), size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(syncError!, style: const TextStyle(
                  color: Color(0xFFEF5350), fontSize: 11.5,
                ))),
              ]),
            ),
          ],
          // Sync timestamp info box
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF3A3A44).withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  lastBillingSyncTime != null
                      ? Icons.cloud_done_outlined
                      : Icons.warning_amber_rounded,
                  size: 15,
                  color: lastBillingSyncTime != null
                      ? const Color(0xFF81C784)
                      : const Color(0xFFFFB74D),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lastBillingSyncTime != null
                        ? '$_effectiveBillingName: Letzter Sync ${AppTopStatusBar.formatSyncTime(lastBillingSyncTime!)}'
                        : '$_effectiveBillingName: Noch nie synchronisiert',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: lastBillingSyncTime != null
                          ? const Color(0xFFB0B0BC)
                          : const Color(0xFFFFB74D),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Sync button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSyncing ? null : onSync,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFFFFA726)),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(_isSyncing
                  ? 'Synchronisiere…'
                  : '$_effectiveBillingName synchronisieren'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFA726),
                side: BorderSide(
                    color: const Color(0xFFFFA726).withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// B. Heating Curve Chart Section
// ═══════════════════════════════════════════════════════════════════════════

class _HeatingCurveSection extends StatelessWidget {
  final double parallelShift;
  final double currentOutdoorTemp;
  final double currentFlowTemp;

  const _HeatingCurveSection({
    required this.parallelShift,
    required this.currentOutdoorTemp,
    required this.currentFlowTemp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Row(
            children: [
              const Icon(Icons.show_chart_rounded,
                  color: Color(0xFFFFA726), size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Heizkurve & Betriebspunkt',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: Color(0xFFECECF0),
                  ),
                ),
              ),
              // Shift badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFA726).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Shift: ${parallelShift > 0 ? '+' : ''}${parallelShift.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Color(0xFFFFA726),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Chart
          HeatingCurveChart(
            parallelShift: parallelShift,
            currentOutdoorTemp: currentOutdoorTemp,
            currentFlowTemp: currentFlowTemp,
          ),
          const SizedBox(height: 12),

          // Legend
          HeatingCurveLegend(
            parallelShift: parallelShift,
            currentOutdoorTemp: currentOutdoorTemp,
            currentFlowTemp: currentFlowTemp,
          ),

          // Operating point label
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF7C4DFF),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Dein aktueller Betriebspunkt: '
                    '${currentOutdoorTemp.toStringAsFixed(1)}°C Außen → '
                    '${currentFlowTemp.toStringAsFixed(1)}°C Vorlauf',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
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

/// Real controller curve with the live preview from the home slider, what the
/// previewed setpoint means per year, and a fixed "what can I save" table –
/// all based on the annual heating consumption (last 12 months if known).
class HeatingSimulationCard extends StatelessWidget {
  final ControllerHeatingCurve curve;
  final double roomSetpoint;
  final double? previewSetpoint;
  final double outdoorTemp;
  final double? annualHeatingKwh;
  final String? annualHeatingKwhSource;
  final double? pricePerKwh;
  final VoidCallback? onEditAnnualKwh;
  final VoidCallback? onOpenAssistant;
  final BuildingReference? buildingReference;
  final VoidCallback? onPickBuildingReference;

  const HeatingSimulationCard({
    super.key,
    required this.curve,
    required this.roomSetpoint,
    required this.previewSetpoint,
    required this.outdoorTemp,
    required this.annualHeatingKwh,
    required this.annualHeatingKwhSource,
    required this.pricePerKwh,
    this.onEditAnnualKwh,
    this.onOpenAssistant,
    this.buildingReference,
    this.onPickBuildingReference,
  });

  Widget _legendItem(Color color, String label, {bool dashed = false, bool band = false}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: band ? 8 : 3,
            decoration: BoxDecoration(
              color: band ? color.withValues(alpha: 0.3) : (dashed ? null : color),
              border: dashed ? Border(top: BorderSide(color: color, width: 2)) : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFFBDBDC7))),
        ],
      );

  /// Where the current curve sits relative to the guide band at −8 °C.
  String? _referenceVerdict() {
    final ref = buildingReference;
    if (ref == null) return null;
    final own = curve.flowAt(-8, 20); // guide values are for 20 °C room
    final lo = ref.lowAtMinus8, hi = ref.highAtMinus8;
    final range = '${lo.toStringAsFixed(0)}–${hi.toStringAsFixed(0)} °C';
    final where = own > hi + 0.5
        ? 'über dem Richtwert ($range) – hier steckt Sparpotenzial, wenn alle Räume warm genug bleiben.'
        : own < lo - 0.5
            ? 'unter dem Richtwert ($range) – gut, solange alle Räume warm genug werden.'
            : 'im Richtwert-Bereich ($range).';
    return 'Bei −8 °C außen liefert deine Kurve ${own.toStringAsFixed(0)} °C (bei 20 °C Raum) – $where';
  }

  Widget _savingsTable() {
    const style = TextStyle(fontSize: 12, color: Color(0xFFBDBDC7));
    const head = TextStyle(fontSize: 11.5, color: Color(0xFF9E9EA8), fontWeight: FontWeight.w600);
    final rows = <TableRow>[
      const TableRow(children: [
        Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Raum-Soll', style: head)),
        Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Energie/Jahr', style: head)),
        Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Kosten/Jahr', style: head)),
      ]),
    ];
    for (final delta in const [0.5, 1.0, 2.0]) {
      final target = roomSetpoint - delta;
      final s = RoomTemperatureSavings.estimate(
        currentSetpoint: roomSetpoint,
        newSetpoint: target,
        annualHeatingKwh: annualHeatingKwh,
        pricePerKwh: pricePerKwh,
      );
      rows.add(TableRow(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text('${target.toStringAsFixed(1)} °C (−${delta.toStringAsFixed(1)})', style: style),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            s.kwhPerYear == null
                ? '−${s.percent.toStringAsFixed(0)} %'
                : '−${s.kwhPerYear!.toStringAsFixed(0)} kWh (${s.percent.toStringAsFixed(0)} %)',
            style: style,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            s.euroPerYear == null ? '–' : '−${s.euroPerYear!.toStringAsFixed(0)} €',
            style: const TextStyle(fontSize: 12, color: Color(0xFF66BB6A), fontWeight: FontWeight.w700),
          ),
        ),
      ]));
    }
    return Table(columnWidths: const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(1)}, children: rows);
  }

  @override
  Widget build(BuildContext context) {
    final preview = previewSetpoint;
    final previewing = preview != null && (preview - roomSetpoint).abs() >= 0.25;
    final flowNow = curve.flowAt(outdoorTemp, roomSetpoint);
    final flowPreview = previewing ? curve.flowAt(outdoorTemp, preview) : flowNow;
    final savings = previewing
        ? RoomTemperatureSavings.estimate(
            currentSetpoint: roomSetpoint,
            newSetpoint: preview,
            annualHeatingKwh: annualHeatingKwh,
            pricePerKwh: pricePerKwh,
          )
        : null;
    const muted = TextStyle(fontSize: 11.5, color: Color(0xFF9E9EA8), height: 1.35);

    return Container(
      key: const Key('controllerCurveSection'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.show_chart_rounded, color: Color(0xFFFFA726), size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Heizkurve & Sparpotenzial',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: Color(0xFFECECF0))),
            ),
            Text('Raum-Soll ${roomSetpoint.toStringAsFixed(1)} °C',
                style: const TextStyle(color: Color(0xFFFFA726), fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          ControllerCurveChart(
            curve: curve,
            roomSetpoint: roomSetpoint,
            simulatedSetpoint: preview,
            outdoorTemp: outdoorTemp,
            height: 200,
            reference: buildingReference,
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 4, children: [
            _legendItem(ControllerCurveChart.currentColor, 'Deine Kurve'),
            if (previewing) _legendItem(ControllerCurveChart.simulatedColor, 'Vorschau', dashed: true),
            _legendItem(ControllerCurveChart.factoryColor, 'Danfoss-Werkseinstellung', dashed: true),
            if (buildingReference != null)
              _legendItem(ControllerCurveChart.referenceColor, 'Richtwert EnergieSchweiz', band: true),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(
                buildingReference == null
                    ? 'Wähle deinen Gebäudetyp, um den Richtwert-Bereich (EnergieSchweiz) einzublenden.'
                    : _referenceVerdict()!,
                style: muted,
              ),
            ),
            if (onPickBuildingReference != null)
              TextButton(
                key: const Key('pickBuildingReference'),
                onPressed: onPickBuildingReference,
                child: Text(buildingReference == null ? 'Gebäudetyp' : 'Ändern'),
              ),
          ]),
          const SizedBox(height: 10),
          Text(
            previewing
                ? 'Vorschau ${preview.toStringAsFixed(1)} °C (gestrichelt): Vorlauf bei '
                    '${outdoorTemp.toStringAsFixed(1)} °C außen ${flowNow.toStringAsFixed(1)} → '
                    '${flowPreview.toStringAsFixed(1)} °C. Noch nicht übernommen.'
                : 'Vorlauf jetzt bei ${outdoorTemp.toStringAsFixed(1)} °C außen: '
                    '${flowNow.toStringAsFixed(1)} °C. Bewege oben „Haus Basis-Wärme“, um eine '
                    'andere Einstellung zu simulieren.',
            style: muted,
          ),
          if (savings != null) ...[
            const SizedBox(height: 10),
            ControllerSavingsLine(savings: savings, source: annualHeatingKwhSource),
          ],
          const SizedBox(height: 16),
          const Text('Was kann ich sparen?',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFFECECF0))),
          const SizedBox(height: 8),
          _savingsTable(),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  annualHeatingKwh == null
                      ? 'Für kWh und € fehlt dein Jahresverbrauch: Abrechnung synchronisieren oder eintragen.'
                      : 'Basis: ${annualHeatingKwh!.toStringAsFixed(0)} kWh – ${annualHeatingKwhSource ?? 'Jahresverbrauch'}'
                          '${pricePerKwh != null ? ', ${(pricePerKwh! * 100).toStringAsFixed(1)} ct/kWh' : ''}. '
                          'Faustregel ~6 % je °C, Schätzung.',
                  style: muted,
                ),
              ),
              if (onEditAnnualKwh != null)
                TextButton(
                  key: const Key('editAnnualKwh'),
                  onPressed: onEditAnnualKwh,
                  child: Text(annualHeatingKwh == null ? 'Eintragen' : 'Ändern'),
                ),
            ],
          ),
          if (onOpenAssistant != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('openCurveSimulator'),
                icon: const Icon(Icons.auto_graph_rounded, size: 18),
                label: const Text('Optimierungs-Assistent: niedrigste angenehme Einstellung finden'),
                onPressed: onOpenAssistant,
              ),
            ),
        ],
      ),
    );
  }
}

/// "ca. X % weniger Heizenergie · ≈ Y kWh/Jahr · ≈ Z €/Jahr" with its basis.
class ControllerSavingsLine extends StatelessWidget {
  final RoomTemperatureSavings savings;
  final String? source;

  const ControllerSavingsLine({super.key, required this.savings, required this.source});

  @override
  Widget build(BuildContext context) {
    final saving = savings.percent > 0;
    final color = saving ? const Color(0xFF66BB6A) : const Color(0xFFFF7043);
    final verb = saving ? 'weniger' : 'mehr';
    final parts = <String>['ca. ${savings.percent.abs().toStringAsFixed(0)} % $verb Heizenergie'];
    if (savings.kwhPerYear != null) parts.add('≈ ${savings.kwhPerYear!.abs().toStringAsFixed(0)} kWh/Jahr');
    if (savings.euroPerYear != null) parts.add('≈ ${savings.euroPerYear!.abs().toStringAsFixed(0)} €/Jahr');
    final basis = savings.kwhPerYear == null
        ? 'Für kWh und € den Jahresverbrauch im Sparrechner eintragen oder die Abrechnung synchronisieren.'
        : 'Basis: ${source ?? 'Jahresverbrauch'} und dein kWh-Preis; Faustregel ~6 % je °C.';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(parts.join(' · '), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
          const SizedBox(height: 3),
          Text(basis, style: const TextStyle(fontSize: 11, color: Color(0xFF9E9EA8))),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// C. Savings Advice Card
// ═══════════════════════════════════════════════════════════════════════════

class _SavingsAdviceCard extends StatelessWidget {
  final SavingsAnalysis savings;
  const _SavingsAdviceCard({required this.savings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF66BB6A).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  color: Color(0xFF66BB6A), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Sparpotenzial erkannt',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF66BB6A),
                  ),
                ),
              ),
              // Savings amount
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF66BB6A).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Ca. ${savings.annualSavingsEuro.toStringAsFixed(0)} €/Jahr',
                  style: const TextStyle(
                    color: Color(0xFF66BB6A),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Savings bar visualization
          _SavingsBar(
            currentShift: savings.currentShift,
            idealShift: savings.idealShift,
          ),
          const SizedBox(height: 14),

          // Advice text
          Text(
            savings.adviceText,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.75),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),

          // Stats row
          Row(
            children: [
              _StatChip(
                icon: Icons.trending_down_rounded,
                label: '${savings.stepsToFix} Stufen senken',
                color: const Color(0xFF66BB6A),
              ),
              const SizedBox(width: 10),
              _StatChip(
                icon: Icons.bolt_rounded,
                label: '${(savings.savingsPercent * 100).round()}% Energie',
                color: const Color(0xFFFFA726),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            savings.basedOnActualCost
                ? 'Basierend auf deinen tatsächlichen Heizkosten '
                    '(${savings.annualBaseCost.toStringAsFixed(0)} €/Jahr aus Brunata).'
                : 'Schätzung — synchronisiere Brunata für eine Berechnung '
                    'auf Basis deiner tatsächlichen Kosten.',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavingsBar extends StatelessWidget {
  final double currentShift;
  final double idealShift;

  const _SavingsBar({
    required this.currentShift,
    required this.idealShift,
  });

  @override
  Widget build(BuildContext context) {
    // Map shift -15..+15 to 0..1
    final currentPos = ((currentShift + 15) / 30).clamp(0.0, 1.0);
    final idealPos = ((idealShift + 15) / 30).clamp(0.0, 1.0);

    return Column(
      children: [
        SizedBox(
          height: 24,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Stack(
                children: [
                  // Track
                  Positioned(
                    top: 10,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF42A5F5),
                            Color(0xFF66BB6A),
                            Color(0xFFFFA726),
                            Color(0xFFFF7043),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Ideal marker
                  Positioned(
                    left: idealPos * width - 4,
                    top: 6,
                    child: Container(
                      width: 8,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF66BB6A),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Current marker
                  Positioned(
                    left: currentPos * width - 6,
                    top: 4,
                    child: Container(
                      width: 12,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFA726),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Spar', style: TextStyle(
              fontSize: 9,
              color: Colors.white.withValues(alpha: 0.3),
            )),
            Text('Neutral', style: TextStyle(
              fontSize: 9,
              color: Colors.white.withValues(alpha: 0.3),
            )),
            Text('Komfort', style: TextStyle(
              fontSize: 9,
              color: Colors.white.withValues(alpha: 0.3),
            )),
          ],
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
