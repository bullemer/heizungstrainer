import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/models/holiday_plan.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/holiday_service.dart';

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
    required double preheatHours,
  }) async {
    final provider = context.read<ECLProvider>();
    final now = DateTime.now();
    final end = now.add(duration);

    final savings = _holidayService.calculateSavings(duration: duration);

    final plan = HolidayPlan(
      id: 'plan_${now.millisecondsSinceEpoch}',
      title: title,
      startDateTime: now,
      endDateTime: end,
      setbackShift: setbackShift,
      preheatHours: preheatHours,
      estimatedSavingsKwh: savings['kwh'] ?? 0.0,
      estimatedSavingsEuro: savings['euro'] ?? 0.0,
      createdAt: now,
    );

    HapticFeedback.mediumImpact();
    if (!await _activate(plan, provider)) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _ecoGreen,
          content: Text(
            '✓ $title aktiviert! Vorlauf um ${setbackShift.abs().toStringAsFixed(0)} Stufen abgesenkt.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
  }

  Future<void> _cancelActivePlan() async {
    if (_activePlan == null) return;
    final provider = context.read<ECLProvider>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Abwesenheitsmodus beenden?'),
        content: const Text(
          'Die Heizung schaltet sofort wieder auf die normalen Komfort-Einstellungen um.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accentOrange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Jetzt beenden'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    HapticFeedback.mediumImpact();
    final plan = _activePlan!;
    setState(() => _isLoading = true);

    try {
      await _holidayService.cancelOrFinishPlan(plan: plan, provider: provider);
    } catch (e) {
      await _loadState();
      if (!mounted) return;
      final closeAnyway = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _card,
          title: const Text('Normalbetrieb nicht wiederhergestellt'),
          content: Text(
            '$e\n\nDu kannst es erneut versuchen, sobald der Regler erreichbar ist. '
            'Oder den Plan ohne Änderung am Regler schließen – dann stell die '
            'Parallelverschiebung bitte selbst auf ${plan.normalShift.toStringAsFixed(0)} zurück.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Plan aktiv lassen'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ohne Zurücksetzen schließen'),
            ),
          ],
        ),
      );
      if (closeAnyway == true) {
        await _holidayService.cancelOrFinishPlan(
          plan: plan,
          provider: provider,
          restore: false,
        );
        await _loadState();
      }
      return;
    }
    await _loadState();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(plan.setbackApplied
              ? '✓ Normalbetrieb wiederhergestellt.'
              : '✓ Geplante Abwesenheit verworfen.'),
        ),
      );
    }
  }

  Future<void> _openCustomPlanDialog() async {
    final provider = context.read<ECLProvider>();
    final now = DateTime.now();

    DateTime startDate = now;
    TimeOfDay startTime = TimeOfDay.fromDateTime(now);
    DateTime endDate = now.add(const Duration(days: 3));
    TimeOfDay endTime = const TimeOfDay(hour: 18, minute: 0);
    double setbackShift = -3.0;
    double preheatHours = 4.0;
    String title = 'Eigener Urlaub';

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
            final savings = _holidayService.calculateSavings(
              duration: duration.isNegative ? Duration.zero : duration,
            );

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

                    // Shift slider
                    Text(
                      'Spar-Absenkung: Shift ${setbackShift.toStringAsFixed(0)} (ca. -${(setbackShift.abs() * 5).toStringAsFixed(0)}°C Vorlauf)',
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
                              'Erwartete Ersparnis: ca. ${savings['euro']?.toStringAsFixed(2)} € (${savings['kwh']?.toStringAsFixed(0)} kWh)',
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
                            preheatHours: preheatHours,
                            estimatedSavingsKwh: savings['kwh'] ?? 0.0,
                            estimatedSavingsEuro: savings['euro'] ?? 0.0,
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
                  value: 'Shift ${plan.setbackShift.toStringAsFixed(0)}',
                  color: _ecoGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMiniStat(
                  label: 'Ersparnis ca.',
                  value: '~${plan.estimatedSavingsEuro.toStringAsFixed(2)} €',
                  color: _coolBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMiniStat(
                  label: 'Vorheizen ab',
                  value: '${plan.preheatStartTime.hour.toString().padLeft(2, '0')}:${plan.preheatStartTime.minute.toString().padLeft(2, '0')}',
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
        _buildPresetTile(
          icon: Icons.backpack_outlined,
          title: 'Wochenend-Trip (60 Std.)',
          subtitle: 'Freitag 12:00 → Sonntag 24:00 Uhr · Ca. 16 € Ersparnis',
          onTap: () => _activatePreset(
            title: 'Wochenend-Trip',
            duration: const Duration(hours: 60),
            setbackShift: -3.0,
            preheatHours: 4.0,
          ),
        ),
        const SizedBox(height: 8),
        _buildPresetTile(
          icon: Icons.beach_access_outlined,
          title: '1 Woche Urlaub (7 Tage)',
          subtitle: '168 Std. Abwesenheit · Ca. 46 € Ersparnis',
          onTap: () => _activatePreset(
            title: '1 Woche Urlaub',
            duration: const Duration(days: 7),
            setbackShift: -3.0,
            preheatHours: 5.0,
          ),
        ),
        const SizedBox(height: 8),
        _buildPresetTile(
          icon: Icons.flight_takeoff_outlined,
          title: '2 Wochen Reise (14 Tage)',
          subtitle: '336 Std. Jahresurlaub · Ca. 92 € Ersparnis',
          onTap: () => _activatePreset(
            title: '2 Wochen Reise',
            duration: const Duration(days: 14),
            setbackShift: -3.0,
            preheatHours: 6.0,
          ),
        ),
        const SizedBox(height: 8),
        _buildPresetTile(
          icon: Icons.bolt_outlined,
          title: 'Kurztrip / Tagesabwesenheit (12 Std.)',
          subtitle: 'Ganztägig außer Haus · Ca. 3,50 € Ersparnis',
          onTap: () => _activatePreset(
            title: 'Kurztrip (12 Std.)',
            duration: const Duration(hours: 12),
            setbackShift: -2.0,
            preheatHours: 2.0,
          ),
        ),
      ],
    );
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
