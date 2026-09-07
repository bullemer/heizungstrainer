import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/ecl_reading.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/widgets/sparkline_chart.dart';

/// Polished dashboard displaying live ECL 310 sensor readings with
/// sparkline trends, color-coded heat indicators, and setpoint controls.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            const Text('Heizungstrainer'),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 2,
        actions: [
          Consumer<ECLProvider>(
            builder: (context, provider, _) => IconButton(
              onPressed: provider.refreshReadings,
              icon: const Icon(Icons.refresh),
              tooltip: 'Aktualisieren',
            ),
          ),
          Consumer<ECLProvider>(
            builder: (context, provider, _) => PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'disconnect') {
                  provider.disconnect();
                  Navigator.of(context).pushReplacementNamed('/');
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'ip',
                  enabled: false,
                  child: Text(
                    provider.controllerIp ?? '—',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'disconnect',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 20),
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ],
          ),
        ),
        child: Consumer<ECLProvider>(
          builder: (context, provider, _) {
            if (!provider.isConnected && provider.readings.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            return RefreshIndicator(
              onRefresh: provider.refreshReadings,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // ── Header info ─────────────────────────────
                  _LastUpdateChip(readings: provider.readings),
                  const SizedBox(height: 16),

                  // ── Sensor Cards with Sparklines ────────────
                  _buildSectionHeader(theme, 'Sensorwerte', Icons.sensors),
                  const SizedBox(height: 10),
                  _EnhancedSensorCard(
                    parameter: ECLRegisters.outdoorTemp,
                    reading: provider.getReading(ECLRegisters.outdoorTemp),
                    history: provider.getHistory(ECLRegisters.outdoorTemp),
                    icon: Icons.wb_sunny_outlined,
                    label: 'Außen',
                    colorMapper: getTemperatureColor,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _CompactSensorCard(
                          parameter: ECLRegisters.flowTemp,
                          reading: provider.getReading(ECLRegisters.flowTemp),
                          history: provider.getHistory(ECLRegisters.flowTemp),
                          icon: Icons.arrow_upward_rounded,
                          label: 'Vorlauf',
                          colorMapper: getFlowTemperatureColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _CompactSensorCard(
                          parameter: ECLRegisters.returnTemp,
                          reading: provider.getReading(ECLRegisters.returnTemp),
                          history: provider.getHistory(ECLRegisters.returnTemp),
                          icon: Icons.arrow_downward_rounded,
                          label: 'Rücklauf',
                          colorMapper: getFlowTemperatureColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // ── Setpoint Controls ───────────────────────
                  _buildSectionHeader(theme, 'Sollwerte', Icons.tune),
                  const SizedBox(height: 10),
                  _SetpointCard(
                    parameter: ECLRegisters.roomTargetTemp,
                    reading: provider.getReading(ECLRegisters.roomTargetTemp),
                    icon: Icons.thermostat,
                    accentColor: Colors.orange,
                  ),
                  const SizedBox(height: 12),
                  _SetpointCard(
                    parameter: ECLRegisters.heatingCurveShift,
                    reading:
                        provider.getReading(ECLRegisters.heatingCurveShift),
                    icon: Icons.show_chart,
                    accentColor: Colors.deepPurple,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Last Update Chip
// ────────────────────────────────────────────────────────────────────────────

class _LastUpdateChip extends StatelessWidget {
  final Map<String, ECLReading> readings;
  const _LastUpdateChip({required this.readings});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final latestTime = readings.values.isEmpty
        ? null
        : readings.values
            .map((r) => r.timestamp)
            .reduce((a, b) => a.isAfter(b) ? a : b);

    final timeStr = latestTime != null
        ? '${latestTime.hour.toString().padLeft(2, '0')}:'
          '${latestTime.minute.toString().padLeft(2, '0')}:'
          '${latestTime.second.toString().padLeft(2, '0')}'
        : '—';

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'Letzte Aktualisierung: $timeStr',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Enhanced Sensor Card (full width, with sparkline)
// ────────────────────────────────────────────────────────────────────────────

class _EnhancedSensorCard extends StatelessWidget {
  final ECLParameter parameter;
  final ECLReading? reading;
  final List<double> history;
  final IconData icon;
  final String label;
  final Color Function(double) colorMapper;

  const _EnhancedSensorCard({
    required this.parameter,
    required this.reading,
    required this.history,
    required this.icon,
    required this.label,
    required this.colorMapper,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final temp = reading?.displayValue ?? 0;
    final accentColor = colorMapper(temp);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: accentColor.withValues(alpha: 0.3),
        ),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Heat indicator dot
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accentColor,
                        accentColor.withValues(alpha: 0.7),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        parameter.name,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                // Temperature value
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      reading != null
                          ? temp.toStringAsFixed(1)
                          : '—',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                    Text(
                      parameter.unit,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Sparkline
            if (history.length >= 2) ...[
              const SizedBox(height: 16),
              SparklineChart(
                data: history,
                lineColor: accentColor,
                fillColor: accentColor.withValues(alpha: 0.15),
                height: 50,
                strokeWidth: 2.5,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_minutesAgo(history.length)} Min',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    'Jetzt',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _minutesAgo(int dataPoints) {
    final minutes = (dataPoints * 10 / 60).round();
    return '-$minutes';
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Compact Sensor Card (half width, with mini sparkline)
// ────────────────────────────────────────────────────────────────────────────

class _CompactSensorCard extends StatelessWidget {
  final ECLParameter parameter;
  final ECLReading? reading;
  final List<double> history;
  final IconData icon;
  final String label;
  final Color Function(double) colorMapper;

  const _CompactSensorCard({
    required this.parameter,
    required this.reading,
    required this.history,
    required this.icon,
    required this.label,
    required this.colorMapper,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final temp = reading?.displayValue ?? 0;
    final accentColor = colorMapper(temp);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: accentColor.withValues(alpha: 0.25),
        ),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon + label
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withValues(alpha: 0.12),
                  ),
                  child: Icon(icon, color: accentColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Temperature
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  reading != null ? temp.toStringAsFixed(1) : '—',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    parameter.unit,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            // Mini sparkline
            if (history.length >= 2) ...[
              const SizedBox(height: 10),
              SparklineChart(
                data: history,
                lineColor: accentColor,
                height: 30,
                strokeWidth: 1.5,
              ),
            ],
            // Heat bar
            const SizedBox(height: 8),
            _HeatBar(value: temp, color: accentColor),
          ],
        ),
      ),
    );
  }
}

/// A thin gradient bar that visually indicates the heat level.
class _HeatBar extends StatelessWidget {
  final double value;
  final Color color;

  const _HeatBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    // Map temperature to 0.0-1.0 range (0°C to 80°C)
    final fraction = ((value / 80.0).clamp(0.0, 1.0));

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 4,
        child: LinearProgressIndicator(
          value: fraction,
          backgroundColor: color.withValues(alpha: 0.1),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Setpoint Control Card
// ────────────────────────────────────────────────────────────────────────────

class _SetpointCard extends StatefulWidget {
  final ECLParameter parameter;
  final ECLReading? reading;
  final IconData icon;
  final Color accentColor;

  const _SetpointCard({
    required this.parameter,
    required this.reading,
    required this.icon,
    required this.accentColor,
  });

  @override
  State<_SetpointCard> createState() => _SetpointCardState();
}

class _SetpointCardState extends State<_SetpointCard> {
  late double _sliderValue;
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _sliderValue =
        widget.reading?.displayValue ?? widget.parameter.minValue ?? 0;
  }

  @override
  void didUpdateWidget(covariant _SetpointCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && widget.reading != null) {
      _sliderValue = widget.reading!.displayValue;
    }
  }

  Future<void> _saveValue() async {
    setState(() => _isSaving = true);
    try {
      await context.read<ECLProvider>().writeParameter(
            widget.parameter,
            _sliderValue,
          );
      if (mounted) {
        setState(() { _isEditing = false; _isSaving = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${widget.parameter.name} gespeichert'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ));
      }
    } on ParameterBoundsException catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } on ModbusCommunicationException catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final param = widget.parameter;
    final min = param.minValue ?? -15;
    final max = param.maxValue ?? 15;
    final divisions = ((max - min) / (param.multiplier < 1 ? 0.5 : 1)).round();
    final currentDisplay = widget.reading?.formattedValue ?? '—';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: _isEditing
              ? widget.accentColor.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: _isEditing ? 1.5 : 1,
        ),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: widget.accentColor.withValues(alpha: 0.12),
                  ),
                  child: Icon(widget.icon, color: widget.accentColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(param.name, style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600, color: colorScheme.onSurface,
                      )),
                      const SizedBox(height: 2),
                      Text('Aktuell: $currentDisplay',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isEditing)
                  Text(
                    '${_sliderValue.toStringAsFixed(param.displayPrecision)}'
                    '${param.unit.isNotEmpty ? ' ${param.unit}' : ''}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: widget.accentColor,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: widget.accentColor,
                inactiveTrackColor: widget.accentColor.withValues(alpha: 0.15),
                thumbColor: widget.accentColor,
                overlayColor: widget.accentColor.withValues(alpha: 0.12),
                trackHeight: 6,
              ),
              child: Slider(
                value: _sliderValue.clamp(min, max),
                min: min, max: max, divisions: divisions,
                label: _sliderValue.toStringAsFixed(param.displayPrecision),
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  setState(() { _sliderValue = v; _isEditing = true; });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${min.toStringAsFixed(param.displayPrecision)}'
                      '${param.unit.isNotEmpty ? ' ${param.unit}' : ''}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text('${max.toStringAsFixed(param.displayPrecision)}'
                      '${param.unit.isNotEmpty ? ' ${param.unit}' : ''}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: _isSaving ? null : () {
                    setState(() {
                      _isEditing = false;
                      _sliderValue = widget.reading?.displayValue ?? param.minValue ?? 0;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Abbrechen'),
                )),
                const SizedBox(width: 12),
                Expanded(child: FilledButton.icon(
                  onPressed: _isSaving ? null : _saveValue,
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Sende…' : 'Speichern'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: widget.accentColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
