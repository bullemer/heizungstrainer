import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/settings_screen.dart';
import 'package:heizungstrainer/widgets/app_top_status_bar.dart';

/// Connection & auto-discovery screen.
///
/// Animates through the discovery lifecycle:
/// disconnected → scanning (with progress) → connecting → success → navigate.
/// Provides manual IP entry as a fallback.
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen>
    with SingleTickerProviderStateMixin {
  final _ipController = TextEditingController();
  bool _showManualEntry = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  void _startDiscovery() {
    setState(() => _showManualEntry = false);
    context.read<ECLProvider>().connectToController();
  }

  void _connectManual() {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    // Basic IP validation
    final parts = ip.split('.');
    if (parts.length != 4 || parts.any((p) => int.tryParse(p) == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte gültige IP-Adresse eingeben (z.B. 192.168.1.100)'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    context.read<ECLProvider>().connectToIp(ip);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Consumer<ECLProvider>(
        builder: (context, provider, _) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.surface,
                  colorScheme.surfaceContainerHighest,
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const AppTopStatusBar(),
                  // ── Top Navigation Bar ──────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          key: const Key('startpage_settings_button'),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            );
                          },
                          icon: const Icon(Icons.settings_outlined, size: 18),
                          label: const Text('Einstellungen', style: TextStyle(fontSize: 13)),
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 16),
                            // ── Logo / Icon ──────────────────────────────
                            _buildHeader(colorScheme, provider),
                      const SizedBox(height: 48),

                      // ── Status Card ──────────────────────────────
                      _buildStatusCard(theme, colorScheme, provider),
                      const SizedBox(height: 24),

                      // ── Manual Entry ─────────────────────────────
                      if (_showManualEntry ||
                          provider.connectionState == ECLConnectionState.error)
                        _buildManualEntry(theme, colorScheme),

                      const SizedBox(height: 16),

                      // ── Action Buttons ───────────────────────────
                      _buildActions(colorScheme, provider),

                      const SizedBox(height: 24),

                      // ── Home-network-only notice ─────────────────
                      _buildNetworkNotice(theme, colorScheme),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  ),
);
  }

  Widget _buildHeader(ColorScheme colorScheme, ECLProvider provider) {
    final isScanning =
        provider.connectionState == ECLConnectionState.discovering;

    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: isScanning ? _pulseAnimation.value : 1.0,
              child: child,
            );
          },
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary,
                  colorScheme.tertiary,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(
              Icons.device_thermostat,
              size: 48,
              color: colorScheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Heizungstrainer',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'ECL Comfort 310',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
              ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(
    ThemeData theme,
    ColorScheme colorScheme,
    ECLProvider provider,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildStatusIcon(colorScheme, provider),
            const SizedBox(height: 16),
            _buildStatusText(theme, colorScheme, provider),
            if (provider.connectionState == ECLConnectionState.discovering) ...[
              const SizedBox(height: 20),
              _buildProgressBar(colorScheme, provider),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(ColorScheme colorScheme, ECLProvider provider) {
    IconData icon;
    Color color;

    switch (provider.connectionState) {
      case ECLConnectionState.disconnected:
        icon = Icons.wifi_find;
        color = colorScheme.onSurfaceVariant;
      case ECLConnectionState.discovering:
        icon = Icons.radar;
        color = colorScheme.primary;
      case ECLConnectionState.connecting:
        icon = Icons.cable;
        color = colorScheme.tertiary;
      case ECLConnectionState.connected:
        icon = Icons.check_circle;
        color = Colors.green;
      case ECLConnectionState.error:
        icon = Icons.error_outline;
        color = colorScheme.error;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Icon(icon, key: ValueKey(icon), size: 40, color: color),
    );
  }

  Widget _buildStatusText(
    ThemeData theme,
    ColorScheme colorScheme,
    ECLProvider provider,
  ) {
    String title;
    String subtitle;

    switch (provider.connectionState) {
      case ECLConnectionState.disconnected:
        title = 'Bereit';
        subtitle = 'Starten Sie die Suche nach Ihrem ECL 310 Regler';
      case ECLConnectionState.discovering:
        title = 'Suche läuft…';
        final pct = (provider.discoveryProgress * 100).toInt();
        subtitle = 'Scanne lokales Netzwerk auf Port 502 ($pct%)';
      case ECLConnectionState.connecting:
        title = 'Verbinde…';
        subtitle = 'Stelle Modbus TCP Verbindung her zu\n${provider.controllerIp}';
      case ECLConnectionState.connected:
        title = 'Verbunden';
        subtitle = 'ECL 310 gefunden unter ${provider.controllerIp}';
      case ECLConnectionState.error:
        title = 'Fehler';
        subtitle = provider.errorMessage ?? 'Unbekannter Fehler';
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Column(
        key: ValueKey(title),
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(ColorScheme colorScheme, ECLProvider provider) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: provider.discoveryProgress > 0
                ? provider.discoveryProgress
                : null,
            minHeight: 6,
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(colorScheme.primary),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(provider.discoveryProgress * 254).toInt()} / 254 Hosts',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildNetworkNotice(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.wifi_rounded, size: 20, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
                children: const [
                  TextSpan(
                    text: 'Nur im Heimnetzwerk nutzbar.\n',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: 'Dein Smartphone muss im selben WLAN wie der '
                        'ECL 310 Regler sein. Der Regler ist aus dem Internet '
                        'nicht erreichbar — unterwegs (Mobilfunk/fremdes WLAN) '
                        'funktioniert die Steuerung nicht.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualEntry(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Manuelle Verbindung',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ipController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '192.168.1.100',
                labelText: 'IP-Adresse des ECL 310',
                prefixIcon: const Icon(Icons.lan),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
              ),
              onSubmitted: (_) => _connectManual(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _connectManual,
              icon: const Icon(Icons.link),
              label: const Text('Verbinden'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(ColorScheme colorScheme, ECLProvider provider) {
    switch (provider.connectionState) {
      case ECLConnectionState.disconnected:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _startDiscovery,
              icon: const Icon(Icons.search),
              label: const Text('Regler suchen'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _showManualEntry = true),
              icon: const Icon(Icons.edit),
              label: const Text('IP manuell eingeben'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            if (provider.hasCachedReadings) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => provider.openOfflineMode(),
                icon: const Icon(Icons.offline_bolt_outlined),
                label: const Text('Offline-Modus (Gespeicherte Daten)'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('startpage_settings_action_button'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Einstellungen (Regler & Abrechnung)'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Without a controller at hand (or for the Play review): try it all simulated.
            TextButton.icon(
              key: const Key('startpage_demo_button'),
              onPressed: () => provider.startSimulation(),
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: const Text('Ohne Regler ausprobieren (Demo)'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        );

      case ECLConnectionState.discovering:
        return OutlinedButton.icon(
          onPressed: () {
            provider.disconnect();
          },
          icon: const Icon(Icons.stop),
          label: const Text('Abbrechen'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            foregroundColor: colorScheme.error,
            side: BorderSide(color: colorScheme.error),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );

      case ECLConnectionState.connecting:
        return const SizedBox.shrink();

      case ECLConnectionState.connected:
        return const SizedBox.shrink();

      case ECLConnectionState.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () {
                provider.clearError();
                _startDiscovery();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut suchen'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _showManualEntry = true),
              icon: const Icon(Icons.edit),
              label: const Text('IP manuell eingeben'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            if (provider.hasCachedReadings) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => provider.openOfflineMode(),
                icon: const Icon(Icons.offline_bolt_outlined),
                label: const Text('Offline-Modus (Gespeicherte Daten)'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('startpage_error_settings_action_button'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Einstellungen (Regler & Abrechnung)'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Without a controller at hand (or for the Play review): try it all simulated.
            TextButton.icon(
              key: const Key('startpage_error_demo_button'),
              onPressed: () => provider.startSimulation(),
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: const Text('Ohne Regler ausprobieren (Demo)'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        );
    }
  }
}
