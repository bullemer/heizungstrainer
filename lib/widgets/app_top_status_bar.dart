import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/settings_screen.dart';

/// Permanent top status bar rendered at the top of the application.
///
/// Displays:
/// 1. Controller connection status:
///    - Successful connection with controller name and IP address.
///    - Failure status when not possible to connect to a controller.
/// 2. Abrechnungsstelle sync status:
///    - Last sync timestamp if synchronization occurred.
///    - Prominent notice when there was never a sync with the Abrechnungsstelle.
/// 3. Direct quick-action link to the Settings section.
///
/// Styled in compact, small fonts (11px) with status-specific icons and colors.
class AppTopStatusBar extends StatelessWidget {
  const AppTopStatusBar({super.key});

  static String formatSyncTime(DateTime time) {
    final now = DateTime.now();
    final isToday = now.year == time.year &&
        now.month == time.month &&
        now.day == time.day;
    final isYesterday = now.year == time.year &&
        now.month == time.month &&
        now.day - time.day == 1;

    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');

    if (isToday) {
      return 'Heute, $hh:$mm Uhr';
    } else if (isYesterday) {
      return 'Gestern, $hh:$mm Uhr';
    } else {
      final dd = time.day.toString().padLeft(2, '0');
      final mo = time.month.toString().padLeft(2, '0');
      return '$dd.$mo.${time.year}, $hh:$mm Uhr';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ECLProvider>(
      builder: (context, provider, _) {
        final isConnected = provider.isConnected;
        final desc = provider.currentControllerDescriptor;
        final controllerName = '${desc.brand} ${desc.model}';
        final controllerIp = provider.controllerIp;

        // 1. Controller connection info
        final String controllerText;
        final IconData controllerIcon;
        final Color controllerColor;

        if (isConnected) {
          final ipStr = (controllerIp != null && controllerIp.isNotEmpty)
              ? controllerIp
              : '127.0.0.1';
          controllerText = 'Verbunden: $controllerName ($ipStr)';
          controllerIcon = Icons.check_circle_rounded;
          controllerColor = const Color(0xFF81C784); // Soft green
        } else if (provider.isReconnecting) {
          controllerText = 'Verbindung verloren: Reconnect läuft...';
          controllerIcon = Icons.sync_problem_rounded;
          controllerColor = const Color(0xFFFFB74D); // Amber
        } else if (provider.connectionState == ECLConnectionState.discovering ||
            provider.connectionState == ECLConnectionState.connecting) {
          controllerText = 'Verbinde mit $controllerName...';
          controllerIcon = Icons.sync_rounded;
          controllerColor = const Color(0xFF64B5F6); // Soft blue
        } else {
          // Connection was not possible / error / offline
          final err = provider.errorMessage;
          if (err != null && err.isNotEmpty) {
            controllerText = 'Verbindung nicht möglich: $err';
          } else {
            controllerText = 'Verbindung nicht möglich: Keine Verbindung zum Regler';
          }
          controllerIcon = Icons.error_outline_rounded;
          controllerColor = const Color(0xFFE57373); // Soft red
        }

        // 2. Abrechnungsstelle sync info
        final billingName = provider.activeBillingProvider.displayName;
        final String billingText;
        final IconData billingIcon;
        final Color billingColor;

        if (provider.isBrunataSyncing) {
          billingText = 'Abrechnungsstelle ($billingName): Synchronisation läuft...';
          billingIcon = Icons.sync_rounded;
          billingColor = const Color(0xFF64B5F6); // Soft blue
        } else if (provider.lastBillingSyncTime != null) {
          final formattedTime = formatSyncTime(provider.lastBillingSyncTime!);
          billingText = 'Abrechnungsstelle ($billingName): Letzter Sync $formattedTime';
          billingIcon = Icons.cloud_done_outlined;
          billingColor = const Color(0xFF81C784); // Soft green
        } else {
          // Never synced with Abrechnungsstelle
          billingText = 'Abrechnungsstelle ($billingName): Noch nie synchronisiert';
          billingIcon = Icons.warning_amber_rounded;
          billingColor = const Color(0xFFFFB74D); // Amber
        }

        return Container(
          key: const Key('app_top_status_bar'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: const BoxDecoration(
            color: Color(0xFF141418),
            border: Border(
              bottom: BorderSide(
                color: Color(0xFF2E2E38),
                width: 1.0,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Controller Status Line
                    Row(
                      children: [
                        Icon(
                          controllerIcon,
                          key: const Key('controller_status_icon'),
                          size: 13,
                          color: controllerColor,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            controllerText,
                            key: const Key('controller_status_text'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: controllerColor,
                              letterSpacing: 0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Abrechnungsstelle Status Line
                    Row(
                      children: [
                        Icon(
                          billingIcon,
                          key: const Key('billing_status_icon'),
                          size: 13,
                          color: billingColor,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            billingText,
                            key: const Key('billing_status_text'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: billingColor,
                              letterSpacing: 0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('top_bar_settings_button'),
                icon: const Icon(
                  Icons.settings_outlined,
                  size: 18,
                  color: Color(0xFF9E9EA8),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                splashRadius: 18,
                tooltip: 'Einstellungen',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
