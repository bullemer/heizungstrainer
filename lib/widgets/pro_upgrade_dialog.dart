import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/license_service.dart';

/// Modal bottom sheet that explains Pro benefits and unlocks Pro with an
/// offline licence key.
class ProUpgradeDialog extends StatefulWidget {
  final String? featureHint;

  const ProUpgradeDialog({super.key, this.featureHint});

  /// Helper to present the upgrade modal from any screen.
  static Future<bool?> show(BuildContext context, {String? featureHint}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF23232B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ProUpgradeDialog(featureHint: featureHint),
    );
  }

  @override
  State<ProUpgradeDialog> createState() => _ProUpgradeDialogState();
}

class _ProUpgradeDialogState extends State<ProUpgradeDialog> {
  final _keyController = TextEditingController();
  bool _isVerifying = false;
  String? _errorMessage;

  static const _accentOrange = Color(0xFFFFA726);
  static const _ecoGreen = Color(0xFF66BB6A);
  static const _cardBg = Color(0xFF2A2A34);

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _activateKey(LicenseService licenseService) async {
    final rawKey = _keyController.text.trim();
    if (rawKey.isEmpty) {
      setState(() => _errorMessage = 'Bitte gib deinen Lizenzschlüssel ein.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    HapticFeedback.mediumImpact();
    final success = await licenseService.activateOfflineKey(rawKey);

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: _ecoGreen,
          content: Text(
            '🎉 Heizungstrainer Pro erfolgreich freigeschaltet!',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
      Navigator.pop(context, true);
    } else {
      setState(() {
        _errorMessage = 'Ungültiger Lizenzschlüssel. Bitte den vollständigen Schlüssel '
            '(beginnt mit HT2-) aus der E-Mail kopieren und einfügen.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final eclProvider = context.watch<ECLProvider>();
    final licenseService = eclProvider.licenseService;
    final isPro = licenseService.isPro;

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
            // Top handle & close
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accentOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _accentOrange.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.workspace_premium_rounded, color: _accentOrange, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'PRO VERSION',
                        style: TextStyle(
                          color: _accentOrange,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Main Title
            const Text(
              'Heizungstrainer Pro',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFFECECF0),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.featureHint != null
                  ? '${widget.featureHint} erfordert die Pro-Freischaltung.'
                  : 'Schreibe Parameter direkt in deinen Regler, nutze den Urlaubs-Autopiloten und sichere deine Einstellungen.',
              style: const TextStyle(fontSize: 13.5, color: Color(0xFF9E9EA8), height: 1.4),
            ),
            const SizedBox(height: 18),

            if (isPro) ...[
              // Already Pro Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _ecoGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _ecoGreen.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: _ecoGreen, size: 40),
                    const SizedBox(height: 8),
                    const Text(
                      'Du nutzt bereits Heizungstrainer Pro!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: _ecoGreen,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Quelle: ${licenseService.currentInfo.note ?? licenseService.currentInfo.source.name}',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () async {
                        await licenseService.revokeLicense();
                        if (mounted) setState(() {});
                      },
                      child: const Text('Lizenz von diesem Gerät entfernen'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Feature list
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF3A3A44)),
                ),
                child: const Column(
                  children: [
                    _FeatureRow(
                      icon: Icons.check,
                      iconColor: Colors.white60,
                      title: 'Sensoren & Zähler live lesen',
                      isFree: true,
                    ),
                    Divider(height: 16, color: Color(0xFF3A3A44)),
                    _FeatureRow(
                      icon: Icons.edit_calendar_rounded,
                      iconColor: _accentOrange,
                      title: 'Heizkurven-Shift direkt schreiben',
                      isFree: false,
                    ),
                    Divider(height: 16, color: Color(0xFF3A3A44)),
                    _FeatureRow(
                      icon: Icons.beach_access_rounded,
                      iconColor: _accentOrange,
                      title: 'Urlaubs-Autopilot (Absenken & Vorheizen)',
                      isFree: false,
                    ),
                    Divider(height: 16, color: Color(0xFF3A3A44)),
                    _FeatureRow(
                      icon: Icons.restore_rounded,
                      iconColor: _accentOrange,
                      title: 'Sicherungen erstellen & wiederherstellen',
                      isFree: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Offline licence key
              const Text(
                'Lizenzschlüssel eingeben',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFECECF0),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _keyController,
                      textCapitalization: TextCapitalization.characters,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'HT2-XXXXX-XXXXX-…',
                        errorMaxLines: 3,
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF1E1E24),
                        errorText: _errorMessage,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF3A3A44)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _accentOrange,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _isVerifying ? null : () => _activateKey(licenseService),
                    child: _isVerifying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Text('Aktivieren', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const Text(
                'Noch keinen Schlüssel? Pro (19,99 € einmalig) kannst du über das '
                'Kontaktformular auf heizungstrainer.de/kontakt.html anfragen – du '
                'bekommst den Lizenzschlüssel per E-Mail. Die Aktivierung funktioniert '
                'offline, ohne Konto.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF9E9EA8), height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final bool isFree;

  const _FeatureRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.isFree,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 13, color: Color(0xFFECECF0)),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isFree
                ? Colors.white.withValues(alpha: 0.1)
                : const Color(0xFFFFA726).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            isFree ? 'Free' : 'Pro',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isFree ? Colors.white60 : const Color(0xFFFFA726),
            ),
          ),
        ),
      ],
    );
  }
}
