import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/models/holiday_plan.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/holiday_service.dart';
import 'package:heizungstrainer/widgets/holiday_end_flow.dart';

/// Screen managing holiday, weekend absence, and automatic setback timers.
class HolidayScreen extends StatefulWidget {
  const HolidayScreen({super.key, this.holidayService});

  final HolidayService? holidayService;

  @override
  State<HolidayScreen> createState() => _HolidayScreenState();
}

class _HolidayScreenState extends State<HolidayScreen> {
  late final HolidayService _holidayService;
  HolidayPlan? _activePlan;
  List<HolidayPlan> _allPlans = [];
  bool _isLoading = true;

  static const String _schedulingNote =
      'Absenken und Vorheizen führt die App aus, solange sie geöffnet ist und den '
      'Regler erreicht – zu Hause im WLAN oder unterwegs per WireGuard. Ist er zum '
      'geplanten Zeitpunkt nicht erreichbar, holt die App den Schritt beim nächsten '
      'Verbinden nach. Für pünktliches Vorheizen die App also rechtzeitig verbinden '
      'oder den Plan von unterwegs beenden.';

  // ── Theme Palette ────────────────────────────────────────────────────────
  static const Color _card = Color(0xFF2A2A32);
  static const Color _border = Color(0xFF3A3A44);
  static const Color _accentOrange = Color(0xFFFFA726);
  static const Color _ecoGreen = Color(0xFF66BB6A);
  static const Color _coolBlue = Color(0xFF42A5F5);
  static const Color _textPrimary = Color(0xFFECECF0);
  static const Color _textSecondary = Color(0xFF9E9EA8);

  @override
  void initState() {
    super.initState();
    _holidayService = widget.holidayService ?? HolidayService();
    HolidayService.changes.addListener(_loadState);
    _loadState();
  }

  @override
  void dispose() {
    HolidayService.changes.removeListener(_loadState);
    super.dispose();
  }

  /// Preheat time: floor heating stores heat in the screed and needs much
  /// longer to come back to temperature than radiators.
  double _preheatFor(ECLProvider provider, double radiatorHours, Duration absence) {
    if (!provider.isFloorHeating) return radiatorHours;
    final floorHours = absence.inHours >= 72 ? 24.0 : 12.0;
    final maxHours = absence.inHours / 2;
    return floorHours > maxHours ? maxHours.floorToDouble() : floorHours;
  }

  AbsenceSavings _savingsFor(
    ECLProvider provider, {
    required DateTime start,
    required DateTime end,
    required double preheatHours,
    required double setbackShift,
    required double roomSetbackKelvin,
  }) {
    final mode = provider.holidayControlMode ?? 'shift';
    return provider.estimateAbsenceSavings(
      start: start,
      preheatStart: end.subtract(Duration(minutes: (preheatHours * 60).round())),
      roomReductionKelvin: provider.roomReductionKelvin(
        mode: mode,
        setbackShift: setbackShift,
        roomSetbackKelvin: roomSetbackKelvin,
      ),
    );
  }

  static String _savingsText(AbsenceSavings s) {
    final parts = <String>['ca. ${s.percent.toStringAsFixed(0)} % weniger Heizenergie während der Absenkung'];
    if (s.kwh != null) parts.add('≈ ${s.kwh!.toStringAsFixed(0)} kWh');
    if (s.euro != null) parts.add('≈ ${s.euro!.toStringAsFixed(2)} €');
    return parts.join(' · ');
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade700,
        content: Text(e.toString()),
      ),
    );
  }

  /// Activates [plan]; returns false (after showing why) if the controller
  /// could not be changed.
  Future<bool> _activate(HolidayPlan plan, ECLProvider provider) async {
    setState(() => _isLoading = true);
    try {
      await _holidayService.activatePlan(plan: plan, provider: provider);
      return true;
    } catch (e) {
      _showError(e);
      return false;
    } finally {
      await _loadState();
    }
  }

  Future<void> _loadState() async {
    final active = await _holidayService.getActivePlan();
    final all = await _holidayService.getAllPlans();
    if (mounted) {
      setState(() {
        _activePlan = active;
        _allPlans = all;
        _isLoading = false;
      });
    }
  }

  Future<void> _activatePreset({
    required String title,
    required Duration duration,
    required double setbackShift,
    required double roomSetbackKelvin,
    required double preheatHours,
  }) async {
    final provider = context.read<ECLProvider>();
    final now = DateTime.now();
    final end = now.add(duration);
    final preheat = _preheatFor(provider, preheatHours, duration);
    final savings = _savingsFor(provider,
        start: now, end: end, preheatHours: preheat, setbackShift: setbackShift, roomSetbackKelvin: roomSetbackKelvin);

    final plan = HolidayPlan(
      id: 'plan_${now.millisecondsSinceEpoch}',
      title: title,
      startDateTime: now,
      endDateTime: end,
      setbackShift: setbackShift,
      roomSetbackKelvin: roomSetbackKelvin,
      preheatHours: preheat,
      estimatedSavingsKwh: savings.kwh ?? 0.0,
      estimatedSavingsEuro: savings.euro ?? 0.0,
      createdAt: now,
    );

    HapticFeedback.mediumImpact();
    if (!await _activate(plan, provider)) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _ecoGreen,
          content: Text(
            provider.holidayControlMode == 'room'
                ? '✓ $title aktiviert! Raum-Sollwert um ${roomSetbackKelvin.toStringAsFixed(1)} °C abgesenkt.'
                : '✓ $title aktiviert! Vorlauf um ${setbackShift.abs().toStringAsFixed(0)} Stufen abgesenkt.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
  }

  Future<void> _cancelActivePlan() async {
    final plan = _activePlan;
    if (plan == null) return;
    setState(() => _isLoading = true);
    await endHolidayPlanWithConfirmation(
      context,
      plan: plan,
      service: _holidayService,
      provider: context.read<ECLProvider>(),
    );
    await _loadState();
  }

  Future<void> _openCustomPlanDialog() async {
    final provider = context.read<ECLProvider>();
    final now = DateTime.now();

    DateTime startDate = now;
    TimeOfDay startTime = TimeOfDay.fromDateTime(now);
    DateTime endDate = now.add(const Duration(days: 3));
    TimeOfDay endTime = const TimeOfDay(hour: 18, minute: 0);
    double setbackShift = -3.0;
    double roomSetbackKelvin = 4.0;
    String title = 'Eigener Urlaub';
    final roomMode = provider.holidayControlMode == 'room';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final startCombined = DateTime(
              startDate.year,
              startDate.month,
              startDate.day,
              startTime.hour,
              startTime.minute,
            );
            final endCombined = DateTime(
              endDate.year,
              endDate.month,
              endDate.day,
              endTime.hour,
              endTime.minute,
            );
            final duration = endCombined.difference(startCombined);
            final preheatHours = _preheatFor(provider, 4.0, duration.isNegative ? Duration.zero : duration);
            final savings = _savingsFor(provider,
                start: startCombined,
                end: endCombined,
                preheatHours: preheatHours,
                setbackShift: setbackShift,
                roomSetbackKelvin: roomSetbackKelvin);

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '🌴 Abwesenheit planen',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: _textSecondary),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Title
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Bezeichnung',
                        filled: true,
                        fillColor: Color(0xFF1E1E24),
                        border: OutlineInputBorder(),
                      ),
                      controller: TextEditingController(text: title),
                      onChanged: (v) => title = v.trim().isEmpty ? 'Urlaub' : v,
                    ),
                    const SizedBox(height: 16),

                    // Date range pickers
                    ListTile(
                      tileColor: const Color(0xFF1E1E24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: const Icon(Icons.flight_takeoff, color: _accentOrange),
                      title: const Text('Abreise / Start'),
                      subtitle: Text(
                        '${startDate.day}.${startDate.month}.${startDate.year} um ${startTime.format(context)}',
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: startDate,
                          firstDate: now.subtract(const Duration(days: 1)),
                          lastDate: now.add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setModalState(() => startDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 10),

                    ListTile(
                      tileColor: const Color(0xFF1E1E24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: const Icon(Icons.flight_land, color: _ecoGreen),
                      title: const Text('Rückkehr / Ende'),
                      subtitle: Text(
                        '${endDate.day}.${endDate.month}.${endDate.year} um ${endTime.format(context)}',
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: endDate,
                          firstDate: startDate,
                          lastDate: now.add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setModalState(() => endDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Setback amount
                    if (roomMode) ...[
                      Text(
                        'Raumtemperatur absenken um ${roomSetbackKelvin.toStringAsFixed(1)} °C'
                        '${provider.getReading(ECLRegisters.roomTargetTemp) != null ? ' (von ${provider.getReading(ECLRegisters.roomTargetTemp)!.displayValue.toStringAsFixed(1)} auf ${(provider.getReading(ECLRegisters.roomTargetTemp)!.displayValue - roomSetbackKelvin).clamp(HolidayService.minHolidayRoomSetpoint, 30).toStringAsFixed(1)} °C)' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Slider(
                        value: roomSetbackKelvin,
                        min: 1.0,
                        max: 6.0,
                        divisions: 10,
                        activeColor: _ecoGreen,
                        onChanged: (v) => setModalState(() => roomSetbackKelvin = v),
                      ),
                    ] else ...[
                      Text(
                        'Spar-Absenkung: Parallelverschiebung ${setbackShift.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Slider(
                        value: setbackShift,
                        min: -5.0,
                        max: -1.0,
                        divisions: 4,
                        activeColor: _ecoGreen,
                        onChanged: (v) => setModalState(() => setbackShift = v),
                      ),
                    ],
                    Text(
                      'Vorheizen ${preheatHours.toStringAsFixed(0)} Std. vor Rückkehr'
                      '${provider.isFloorHeating ? ' – Fußbodenheizung braucht länger zum Aufheizen' : ''}.',
                      style: const TextStyle(fontSize: 12, color: _textSecondary),
                    ),
                    const SizedBox(height: 12),

                    // Savings banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _ecoGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _ecoGreen.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.eco_rounded, color: _ecoGreen),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _savingsText(savings),
                              style: const TextStyle(
                                color: _ecoGreen,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _accentOrange,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          if (endCombined.isBefore(startCombined)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Rückkehr muss nach der Abreise liegen.'),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(context);

                          final plan = HolidayPlan(
                            id: 'plan_${now.millisecondsSinceEpoch}',
                            title: title,
                            startDateTime: startCombined,
                            endDateTime: endCombined,
                            setbackShift: setbackShift,
                            roomSetbackKelvin: roomSetbackKelvin,
                            preheatHours: preheatHours,
                            estimatedSavingsKwh: savings.kwh ?? 0.0,
                            estimatedSavingsEuro: savings.euro ?? 0.0,
                            createdAt: now,
                          );

                          await _activate(plan, provider);
                        },
                        child: Text(
                          startCombined.isAfter(DateTime.now())
                              ? 'Abwesenheit planen'
                              : 'Jetzt absenken',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(_schedulingNote,
                        style: TextStyle(fontSize: 12, color: _textSecondary)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when readings / consumption data change (preset savings, mode).
    context.watch<ECLProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('🌴 Urlaub & Abwesenheit'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildActivePlanCard(),
                const SizedBox(height: 20),
                _buildPresetsSection(),
                const SizedBox(height: 20),
                _buildSeasonalSavings(),
                const SizedBox(height: 20),
                _buildLocalFirstNotice(),
                const SizedBox(height: 20),
                _buildHistorySection(),
              ],
            ),
    );
  }

  Widget _buildActivePlanCard() {
    final plan = _activePlan;
    final now = DateTime.now();

    if (plan == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.home_outlined, color: _textSecondary, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Normalbetrieb aktiv',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                      Text(
                        'Kein Urlaubs- oder Abwesenheits-Timer programmiert.',
                        style: TextStyle(fontSize: 12.5, color: _textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_alarm_rounded, color: _accentOrange),
                label: const Text('Eigene Abwesenheit planen'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accentOrange,
                  side: const BorderSide(color: _accentOrange),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _openCustomPlanDialog,
              ),
            ),
          ],
        ),
      );
    }

    final isPreheating = plan.isPreheatingActive(now);
    final isArmed = !plan.setbackApplied;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPreheating ? _accentOrange : _ecoGreen,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isPreheating ? _accentOrange : _ecoGreen).withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isPreheating ? _accentOrange : _ecoGreen).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: (isPreheating ? _accentOrange : _ecoGreen).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPreheating ? Icons.local_fire_department : Icons.eco_rounded,
                      size: 14,
                      color: isPreheating ? _accentOrange : _ecoGreen,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isArmed
                          ? 'Geplant ab ${plan.startDateTime.day}.${plan.startDateTime.month}. ${plan.startDateTime.hour.toString().padLeft(2, '0')}:${plan.startDateTime.minute.toString().padLeft(2, '0')}'
                          : isPreheating
                              ? 'Vorheizen fällig'
                              : 'Sparbetrieb aktiv',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isPreheating ? _accentOrange : _ecoGreen,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent),
                onPressed: _cancelActivePlan,
                tooltip: 'Plan beenden',
              ),
            ],
          ),
          const SizedBox(height: 12),

          Text(
            plan.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 4),

          Text(
            'Rückkehr: ${plan.endDateTime.day}.${plan.endDateTime.month}.${plan.endDateTime.year} um ${plan.endDateTime.hour.toString().padLeft(2, '0')}:${plan.endDateTime.minute.toString().padLeft(2, '0')} Uhr',
            style: const TextStyle(fontSize: 13, color: _textSecondary),
          ),
          const SizedBox(height: 16),

          // Metrics grid
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  label: 'Absenkung',
                  value: plan.setbackApplied && plan.controlMode == 'room'
                      ? 'auf ${plan.targetRoomTemp.toStringAsFixed(1)} °C'
                      : (plan.controlMode == 'room' || context.read<ECLProvider>().holidayControlMode == 'room')
                          ? '−${plan.roomSetbackKelvin.toStringAsFixed(1)} °C'
                          : 'Shift ${plan.setbackShift.toStringAsFixed(0)}',
                  color: _ecoGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMiniStat(
                  label: 'Ersparnis ca.',
                  value: plan.estimatedSavingsEuro > 0
                      ? '~${plan.estimatedSavingsEuro.toStringAsFixed(2)} €'
                      : '–',
                  color: _coolBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMiniStat(
                  label: 'Vorheizen ab',
                  value: _whenText(plan.preheatStartTime),
                  color: _accentOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.withValues(alpha: 0.15),
                foregroundColor: Colors.redAccent,
              ),
              onPressed: _cancelActivePlan,
              child: Text(isArmed
                  ? 'Geplante Abwesenheit verwerfen'
                  : 'Vorzeitig beenden & Heizung hochfahren'),
            ),
          ),
          const SizedBox(height: 10),
          const Text(_schedulingNote,
              style: TextStyle(fontSize: 11.5, color: _textSecondary)),
        ],
      ),
    );
  }

  /// "13:08" today, otherwise "12.10. 01:08".
  static String _whenText(DateTime t) {
    final now = DateTime.now();
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? hm : '${t.day}.${t.month}. $hm';
  }

  Widget _buildMiniStat({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: _textSecondary)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// What one week away saves depending on the month – based on the same
  /// month of the comparable previous billing period.
  Widget _buildSeasonalSavings() {
    final provider = context.read<ECLProvider>();
    const preset = _HolidayPreset(Icons.beach_access_outlined, '', '1 Woche Urlaub', Duration(days: 7), -3.0, 4.0, 5.0);
    final roomMode = provider.holidayControlMode == 'room';
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
    const muted = TextStyle(fontSize: 12, color: _textSecondary);
    final hasProfile = provider.heatingMonthlyProfile != null;
    final hasAnnual = provider.annualHeatingKwh != null;

    final rows = <TableRow>[
      const TableRow(children: [
        Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Start im', style: muted)),
        Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Energie', style: muted)),
        Padding(padding: EdgeInsets.only(bottom: 6), child: Text('Kosten', style: muted)),
      ]),
    ];
    for (final start in seasonalTableStarts(now)) {
      final m = start.month;
      final year = start.year;
      final end = start.add(preset.duration);
      final s = _savingsFor(provider,
          start: start,
          end: end,
          preheatHours: _preheatFor(provider, preset.preheatHours, preset.duration),
          setbackShift: preset.setbackShift,
          roomSetbackKelvin: preset.roomSetbackKelvin);
      const cell = TextStyle(fontSize: 12.5, color: _textPrimary);
      rows.add(TableRow(children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('${months[m - 1]} $year', style: cell)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(s.kwh == null ? '–' : '−${s.kwh!.toStringAsFixed(0)} kWh', style: cell),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(s.euro == null ? '–' : '−${s.euro!.toStringAsFixed(2)} €',
              style: const TextStyle(fontSize: 12.5, color: _ecoGreen, fontWeight: FontWeight.w700)),
        ),
      ]));
    }

    return Container(
      key: const Key('seasonalSavings'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Was spart 1 Woche Urlaub – nach Monat',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _textPrimary)),
          const SizedBox(height: 4),
          Text(
            roomMode
                ? 'Raum-Sollwert −${preset.roomSetbackKelvin.toStringAsFixed(0)} °C, 7 Tage, Vorheizen eingerechnet.'
                : 'Parallelverschiebung ${preset.setbackShift.toStringAsFixed(0)}, 7 Tage, Vorheizen eingerechnet.',
            style: muted,
          ),
          const SizedBox(height: 10),
          if (!hasAnnual)
            const Text(
              'Für kWh und € fehlt dein Jahresverbrauch: Abrechnung (Brunata) synchronisieren oder '
              'auf der Startseite unter „Heizkurve & Sparpotenzial“ eintragen.',
              style: muted,
            )
          else ...[
            Table(columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)}, children: rows),
            const SizedBox(height: 8),
            Text(
              hasProfile
                  ? 'Basis: Verbrauch des jeweiligen Monats im vergleichbaren Vorjahres-Abrechnungszeitraum '
                      '(Brunata), skaliert auf ${provider.annualHeatingKwh!.toStringAsFixed(0)} kWh/Jahr; ~6 % je °C.'
                  : 'Kein Monatsprofil aus der Abrechnung – Jahresverbrauch gleichmäßig verteilt. Mit Brunata-'
                      'Synchronisation wird es saisonal (Winter spart deutlich mehr als Sommer).',
              style: muted,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPresetsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Schnellstart (Presets)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        for (final p in _presets) ...[
          _buildPresetTile(
            icon: p.icon,
            title: p.title,
            subtitle: _presetSubtitle(p),
            onTap: () => _confirmPreset(p),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  static const _presets = [
    _HolidayPreset(Icons.backpack_outlined, 'Wochenend-Trip (60 Std.)', 'Wochenend-Trip',
        Duration(hours: 60), -3.0, 4.0, 4.0),
    _HolidayPreset(Icons.beach_access_outlined, '1 Woche Urlaub (7 Tage)', '1 Woche Urlaub',
        Duration(days: 7), -3.0, 4.0, 5.0),
    _HolidayPreset(Icons.flight_takeoff_outlined, '2 Wochen Reise (14 Tage)', '2 Wochen Reise',
        Duration(days: 14), -3.0, 4.0, 6.0),
    _HolidayPreset(Icons.bolt_outlined, 'Kurztrip / Tagesabwesenheit (12 Std.)', 'Kurztrip (12 Std.)',
        Duration(hours: 12), -2.0, 2.0, 2.0),
  ];

  /// A preset writes to the heating right away – ask first, showing exactly
  /// what will change (an accidental tap must not lower the heating).
  Future<void> _confirmPreset(_HolidayPreset p) async {
    final provider = context.read<ECLProvider>();
    final roomMode = provider.holidayControlMode == 'room';
    final current = provider.getReading(ECLRegisters.roomTargetTemp)?.displayValue;
    final change = roomMode && current != null
        ? 'Raum-Sollwert ${current.toStringAsFixed(1)} → '
            '${(current - p.roomSetbackKelvin).clamp(HolidayService.minHolidayRoomSetpoint, 30).toStringAsFixed(1)} °C'
        : 'Parallelverschiebung ${p.setbackShift.toStringAsFixed(0)}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('${p.planTitle} starten?'),
        content: Text('$change ab sofort.\n${_presetSubtitle(p)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            key: const Key('confirmPreset'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Jetzt absenken'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _activatePreset(
      title: p.planTitle,
      duration: p.duration,
      setbackShift: p.setbackShift,
      roomSetbackKelvin: p.roomSetbackKelvin,
      preheatHours: p.preheatHours,
    );
  }

  /// Savings for starting the preset now, from the real consumption profile.
  String _presetSubtitle(_HolidayPreset p) {
    final provider = context.read<ECLProvider>();
    final now = DateTime.now();
    final roomMode = provider.holidayControlMode == 'room';
    final preheat = _preheatFor(provider, p.preheatHours, p.duration);
    final s = _savingsFor(provider,
        start: now,
        end: now.add(p.duration),
        preheatHours: preheat,
        setbackShift: p.setbackShift,
        roomSetbackKelvin: p.roomSetbackKelvin);
    final setback = roomMode
        ? '−${p.roomSetbackKelvin.toStringAsFixed(0)} °C Raum'
        : 'Shift ${p.setbackShift.toStringAsFixed(0)}';
    final money = s.euro != null
        ? '≈ ${s.euro!.toStringAsFixed(2)} € (${s.kwh!.toStringAsFixed(0)} kWh)'
        : 'ca. ${s.percent.toStringAsFixed(0)} % weniger während der Absenkung';
    return '$setback · Vorheizen ${preheat.toStringAsFixed(0)} Std. · bei Start jetzt $money';
  }

  Widget _buildPresetTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _accentOrange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _accentOrange.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: _accentOrange, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: _textSecondary),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: _textSecondary),
        onTap: onTap,
      ),
    );
  }

  Widget _buildLocalFirstNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.security_rounded, color: _coolBlue, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '100% Local-First & Hardware-Autonomie',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: _textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Die Absenkung wird vor deiner Abreise direkt an deinen Regler übermittelt. Du benötigst unterwegs kein Internet. Tipp: Über eine Fritz!Box WireGuard-Verbindung kannst du deine Rückkehr auch von unterwegs anpassen.',
                  style: TextStyle(fontSize: 11.5, color: _textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    final completed = _allPlans.where((p) => p.isCompleted).toList();
    if (completed.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vergangene Abwesenheiten',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        ...completed.take(5).map((p) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Text(
                      '${p.startDateTime.day}.${p.startDateTime.month}. – ${p.endDateTime.day}.${p.endDateTime.month}.${p.endDateTime.year}',
                      style: const TextStyle(fontSize: 11, color: _textSecondary),
                    ),
                  ],
                ),
                Text(
                  '~${p.estimatedSavingsEuro.toStringAsFixed(2)} €',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _ecoGreen,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}


class _HolidayPreset {
  final IconData icon;
  final String title;
  final String planTitle;
  final Duration duration;
  final double setbackShift;
  final double roomSetbackKelvin;
  final double preheatHours;

  const _HolidayPreset(this.icon, this.title, this.planTitle, this.duration, this.setbackShift,
      this.roomSetbackKelvin, this.preheatHours);
}

/// Start dates for the "1 Woche Urlaub – nach Monat" table: the 10th of each
/// of the next 12 months, chronologically from the current month.
@visibleForTesting
List<DateTime> seasonalTableStarts(DateTime now) => [
      for (var i = 0; i < 12; i++)
        DateTime(now.year + (now.month - 1 + i) ~/ 12, (now.month - 1 + i) % 12 + 1, 10, 8),
    ];
