import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/providers/ecl_provider.dart';

/// Settings for the Brunata portal integration: login credentials and the
/// price-per-kWh tariff used to estimate heating cost.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _priceController = TextEditingController();

  bool _obscurePassword = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentValues();
  }

  Future<void> _loadCurrentValues() async {
    final provider = context.read<ECLProvider>();
    final username = await provider.getBrunataUsername();
    final password = await provider.getBrunataPassword();
    final price = await provider.getPricePerKwh();
    if (!mounted) return;
    setState(() {
      _usernameController.text = username ?? '';
      _passwordController.text = password ?? '';
      // Show with a comma-free, trimmed representation (e.g. "0.1").
      _priceController.text = _formatPrice(price);
      _loading = false;
    });
  }

  String _formatPrice(double price) {
    var s = price.toStringAsFixed(4);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  double? _parsePrice(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  Future<void> _save({required bool sync}) async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final provider = context.read<ECLProvider>();
    await provider.saveBrunataSettings(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      pricePerKwh: _parsePrice(_priceController.text)!,
      syncAfterSave: sync,
    );

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(sync
            ? 'Gespeichert – Synchronisierung gestartet.'
            : 'Einstellungen gespeichert.'),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFA726);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Einstellungen',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: accent))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _SectionHeader(
                    icon: Icons.account_circle_outlined,
                    title: 'Brunata-Zugang',
                    subtitle:
                        'Anmeldedaten für das Brunata-Hamburg-Portal. Sie werden '
                        'verschlüsselt nur auf diesem Gerät gespeichert.',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _usernameController,
                    keyboardType: TextInputType.text,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: _decoration(
                      label: 'Kundennummer / Benutzername',
                      icon: Icons.badge_outlined,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Bitte Kundennummer eingeben'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: _decoration(
                      label: 'Kennwort',
                      icon: Icons.lock_outline_rounded,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Bitte Kennwort eingeben'
                        : null,
                  ),
                  const SizedBox(height: 28),
                  _SectionHeader(
                    icon: Icons.euro_rounded,
                    title: 'Tarif',
                    subtitle:
                        'Das Portal liefert nur den Verbrauch in kWh. Die Kosten '
                        'werden aus diesem Preis pro kWh geschätzt.',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: _decoration(
                      label: 'Preis pro kWh',
                      icon: Icons.sell_outlined,
                      suffixText: '€/kWh',
                    ),
                    validator: (v) {
                      final p = _parsePrice(v ?? '');
                      if (p == null) return 'Bitte gültigen Preis eingeben';
                      if (p <= 0 || p > 5) return 'Preis muss zwischen 0 und 5 liegen';
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _save(sync: true),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: const Text('Speichern & Synchronisieren'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _saving ? null : () => _save(sync: false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFECECF0),
                      minimumSize: const Size.fromHeight(50),
                      side: const BorderSide(color: Color(0xFF3A3A44)),
                    ),
                    child: const Text('Nur speichern'),
                  ),
                ],
              ),
            ),
    );
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    Widget? suffix,
    String? suffixText,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      suffixText: suffixText,
      filled: true,
      fillColor: const Color(0xFF2A2A32),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF3A3A44)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF3A3A44)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFFA726)),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFFFFA726), size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFFECECF0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }
}
