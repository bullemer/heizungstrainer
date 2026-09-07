import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/controllers/generic_modbus_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/models/generic_modbus_config.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/device_registry.dart';
import 'package:heizungstrainer/services/energy_price_service.dart';

/// Hub for hardware controller selection, sub-metering provider configuration,
/// tariff pricing, and offline storage settings.
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

  final _modbusHostController = TextEditingController();
  final _modbusPortController = TextEditingController();
  final _modbusUnitIdController = TextEditingController();
  final _modbusOutdoorRegController = TextEditingController();
  final _modbusFlowRegController = TextEditingController();
  final _modbusReturnRegController = TextEditingController();
  final _modbusHwRegController = TextEditingController();
  final _modbusRoomRegController = TextEditingController();
  final _modbusShiftRegController = TextEditingController();
  String _modbusPresetId = 'standard';
  double _modbusMultiplier = 0.1;
  bool _modbusIsHolding = true;
  bool _testingModbus = false;

  bool _obscurePassword = true;
  bool _loading = true;
  bool _saving = false;
  bool _fetchingMarketPrice = false;
  String? _selectedCarrierId;
  bool _isCustomPrice = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentValues();
  }

  Future<void> _loadCurrentValues() async {
    try {
      final provider = context.read<ECLProvider>();
      final username = await provider.getBrunataUsername();
      final password = await provider.getBrunataPassword();
      final price = await provider.getPricePerKwh();
      final isCustom = await provider.energyPriceService.isCustomPrice();
      final savedCarrierId = await provider.energyPriceService.getSavedCarrierId();

      final modbusCfg = provider.genericModbusConfig;
      _modbusHostController.text = modbusCfg.host;
      _modbusPortController.text = modbusCfg.port.toString();
      _modbusUnitIdController.text = modbusCfg.unitId.toString();
      _modbusOutdoorRegController.text = modbusCfg.outdoorRegister.toString();
      _modbusFlowRegController.text = modbusCfg.flowRegister.toString();
      _modbusReturnRegController.text = modbusCfg.returnRegister.toString();
      _modbusHwRegController.text = modbusCfg.hotWaterRegister.toString();
      _modbusRoomRegController.text =
          modbusCfg.roomTargetRegister?.toString() ?? '';
      _modbusShiftRegController.text =
          modbusCfg.heatingCurveShiftRegister?.toString() ?? '';
      _modbusPresetId = modbusCfg.presetId;
      _modbusMultiplier = modbusCfg.multiplier;
      _modbusIsHolding = modbusCfg.isHoldingRegister;

      if (!mounted) return;
      setState(() {
        _usernameController.text = username ?? '';
        _passwordController.text = password ?? '';
        _priceController.text = _formatPrice(price);
        _selectedCarrierId = savedCarrierId ??
            (provider.selectedBillingId == 'brunata_hamburg'
                ? 'district_heating_hamburg'
                : 'national_average');
        _isCustomPrice = isCustom;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _priceController.text =
            _formatPrice(EnergyPriceService.defaultRealisticPrice);
        _selectedCarrierId = 'district_heating_hamburg';
        _loading = false;
      });
    }
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
    _modbusHostController.dispose();
    _modbusPortController.dispose();
    _modbusUnitIdController.dispose();
    _modbusOutdoorRegController.dispose();
    _modbusFlowRegController.dispose();
    _modbusReturnRegController.dispose();
    _modbusHwRegController.dispose();
    _modbusRoomRegController.dispose();
    _modbusShiftRegController.dispose();
    super.dispose();
  }

  double? _parsePrice(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  Future<void> _fetchDynamicMarketPrice(ECLProvider provider) async {
    setState(() => _fetchingMarketPrice = true);
    try {
      final carrier = await provider.fetchDynamicMarketPrice(
        carrierId: _selectedCarrierId,
      );
      if (!mounted) return;
      setState(() {
        _priceController.text = _formatPrice(carrier.benchmarkPricePerKwh);
        _selectedCarrierId = carrier.id;
        _isCustomPrice = false;
        _fetchingMarketPrice = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Marktpreis für ${carrier.name} übernommen: '
            '${_formatPrice(carrier.benchmarkPricePerKwh)} €/kWh (${carrier.source})',
          ),
          backgroundColor: const Color(0xFF1E2836),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _fetchingMarketPrice = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Abrufen des Marktpreises: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _testGenericModbusConnection() async {
    setState(() => _testingModbus = true);
    final modbusCfg = GenericModbusConfig(
      host: _modbusHostController.text.trim().isEmpty
          ? '192.168.1.50'
          : _modbusHostController.text.trim(),
      port: int.tryParse(_modbusPortController.text.trim()) ?? 502,
      unitId: int.tryParse(_modbusUnitIdController.text.trim()) ?? 1,
      outdoorRegister:
          int.tryParse(_modbusOutdoorRegController.text.trim()) ?? 1,
      flowRegister:
          int.tryParse(_modbusFlowRegController.text.trim()) ?? 2,
      returnRegister:
          int.tryParse(_modbusReturnRegController.text.trim()) ?? 3,
      hotWaterRegister:
          int.tryParse(_modbusHwRegController.text.trim()) ?? 4,
      roomTargetRegister:
          int.tryParse(_modbusRoomRegController.text.trim()),
      heatingCurveShiftRegister:
          int.tryParse(_modbusShiftRegController.text.trim()),
      multiplier: _modbusMultiplier,
      isHoldingRegister: _modbusIsHolding,
      presetId: _modbusPresetId,
    );

    final res = await GenericModbusController.testConnection(modbusCfg);
    if (!mounted) return;
    setState(() => _testingModbus = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Verbindungstest erfolgreich!\n'
            'Vorlauf: ${res['flow'] ?? "-"} °C | '
            'Rücklauf: ${res['return'] ?? "-"} °C | '
            'Außen: ${res['outdoor'] ?? "-"} °C | '
            'WW: ${res['hotWater'] ?? "-"} °C',
          ),
          backgroundColor: const Color(0xFF1B3D2F),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verbindungstest fehlgeschlagen: ${res['error']}'),
          backgroundColor: const Color(0xFF5C1D1D),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _save({required bool sync}) async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final provider = context.read<ECLProvider>();

    if (provider.selectedControllerId == 'generic_modbus') {
      final modbusCfg = GenericModbusConfig(
        host: _modbusHostController.text.trim().isEmpty
            ? '192.168.1.50'
            : _modbusHostController.text.trim(),
        port: int.tryParse(_modbusPortController.text.trim()) ?? 502,
        unitId: int.tryParse(_modbusUnitIdController.text.trim()) ?? 1,
        outdoorRegister:
            int.tryParse(_modbusOutdoorRegController.text.trim()) ?? 1,
        flowRegister:
            int.tryParse(_modbusFlowRegController.text.trim()) ?? 2,
        returnRegister:
            int.tryParse(_modbusReturnRegController.text.trim()) ?? 3,
        hotWaterRegister:
            int.tryParse(_modbusHwRegController.text.trim()) ?? 4,
        roomTargetRegister:
            int.tryParse(_modbusRoomRegController.text.trim()),
        heatingCurveShiftRegister:
            int.tryParse(_modbusShiftRegController.text.trim()),
        multiplier: _modbusMultiplier,
        isHoldingRegister: _modbusIsHolding,
        presetId: _modbusPresetId,
        presetName: GenericModbusConfig.presets
            .firstWhere((p) => p.id == _modbusPresetId,
                orElse: () => GenericModbusConfig.presets.first)
            .name,
      );
      await provider.updateGenericModbusConfig(modbusCfg);
    }

    await provider.saveBillingSettings(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      pricePerKwh: _parsePrice(_priceController.text)!,
      carrierId: _selectedCarrierId,
      isCustom: _isCustomPrice,
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
          'Einstellungen & Hardware',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: accent))
          : Consumer<ECLProvider>(
              builder: (context, provider, _) {
                return Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _ActiveSystemSummary(provider: provider),
                      const SizedBox(height: 24),

                      // ── SECTION 1: HEATING CONTROLLER ─────────────
                      const _SectionHeader(
                        icon: Icons.developer_board_rounded,
                        title: 'Heizungsregler (Hardware)',
                        subtitle:
                            'Wähle das Hardware-Modell deiner Heizung oder wechsle '
                            'in den Simulationsmodus für andere Marken.',
                      ),
                      const SizedBox(height: 12),
                      ...DeviceRegistry.knownControllers.map((controllerDesc) {
                        final isSelected =
                            provider.selectedControllerId == controllerDesc.id;
                        return _ControllerCard(
                          descriptor: controllerDesc,
                          isSelected: isSelected,
                          isConnected: provider.isConnected && isSelected,
                          isConnecting: isSelected &&
                              provider.connectionState ==
                                  ECLConnectionState.connecting,
                          onSelect: () =>
                              provider.setSelectedController(controllerDesc.id),
                          onStartSimulation: () => provider.startSimulation(),
                          onDisconnect: () => provider.disconnect(),
                        );
                      }),
                      if (provider.selectedControllerId == 'generic_modbus') ...[
                        const SizedBox(height: 8),
                        _buildGenericModbusConfigCard(provider),
                      ],
                      const SizedBox(height: 24),

                      // ── SECTION 2: BILLING PROVIDER ───────────────
                      const _SectionHeader(
                        icon: Icons.receipt_long_rounded,
                        title: 'Messdienstleister & Abrechnung',
                        subtitle:
                            'Dienstleister für Heizkostenverteilung und Verbrauchserfassung. '
                            'Unterstützt automatische Portalsynchronisation und Test-Simulationen.',
                      ),
                      const SizedBox(height: 12),
                      ...DeviceRegistry.knownBillingProviders.map((billingDesc) {
                        final isSelected =
                            provider.selectedBillingId == billingDesc.id;
                        return _BillingProviderCard(
                          descriptor: billingDesc,
                          isSelected: isSelected,
                          onSelect: () => provider
                              .setSelectedBillingProvider(billingDesc.id),
                        );
                      }),
                      const SizedBox(height: 16),

                      // Credentials accordion or simulated info
                      if (provider.selectedBillingId == 'brunata_hamburg') ...[
                        _buildBrunataCredentialsFields(),
                      ] else ...[
                        _buildSimulatedBillingNotice(
                          provider.currentBillingDescriptor,
                        ),
                      ],
                      const SizedBox(height: 28),

                      // ── SECTION 3: TARIFF & COST ──────────────────
                      const _SectionHeader(
                        icon: Icons.euro_rounded,
                        title: 'Tarif & Energiepreis',
                        subtitle:
                            'Das Abrechnungsportal liefert den Verbrauch in kWh. '
                            'Die monatlichen Kosten und Einsparungen werden mit '
                            'diesem Arbeitspreis berechnet.',
                      ),
                      const SizedBox(height: 14),
                      _buildTariffCard(provider),
                      const SizedBox(height: 28),

                      // ── SECTION 4: OFFLINE & DATABASE ─────────────
                      const _SectionHeader(
                        icon: Icons.storage_rounded,
                        title: 'Datenpuffer & Offline-Betrieb',
                        subtitle:
                            'Sensordaten und Abrechnungshistorie werden lokal in einer '
                            'SQLite-Datenbank gesichert, um auch ohne Reglerverbindung verfügbar zu sein.',
                      ),
                      const SizedBox(height: 12),
                      _buildDatabaseTile(provider),
                      const SizedBox(height: 32),

                      // ── ACTIONS ───────────────────────────────────
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
                        label: Text(
                          provider.selectedBillingId == 'brunata_hamburg'
                              ? 'Speichern & Synchronisieren'
                              : 'Speichern & Simulation abgleichen',
                        ),
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
                );
              },
            ),
    );
  }

  Widget _buildGenericModbusConfigCard(ECLProvider provider) {
    const accent = Color(0xFFFFA726);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF24242C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.settings_input_component_rounded,
                  color: accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Modbus TCP Register-Konfiguration',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFECECF0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Konfiguriere IP, Port und Register-Adressen passend zu deinem Heizungssystem.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),

          // ── Preset Selector ──────────────────────────────────
          DropdownButtonFormField<String>(
            initialValue: _modbusPresetId,
            decoration: _decoration(
              label: 'Hersteller-Profil / Preset',
              icon: Icons.bookmarks_outlined,
            ),
            dropdownColor: const Color(0xFF2A2A32),
            items: GenericModbusConfig.presets.map((preset) {
              return DropdownMenuItem(
                value: preset.id,
                child: Text(preset.name, style: const TextStyle(fontSize: 13.5)),
              );
            }).toList(),
            onChanged: (id) {
              if (id == null) return;
              final preset =
                  GenericModbusConfig.presets.firstWhere((p) => p.id == id);
              setState(() {
                _modbusPresetId = id;
                _modbusPortController.text = preset.defaultPort.toString();
                _modbusUnitIdController.text = preset.defaultUnitId.toString();
                _modbusOutdoorRegController.text =
                    preset.outdoorRegister.toString();
                _modbusFlowRegController.text = preset.flowRegister.toString();
                _modbusReturnRegController.text =
                    preset.returnRegister.toString();
                _modbusHwRegController.text =
                    preset.hotWaterRegister.toString();
                _modbusRoomRegController.text =
                    preset.roomTargetRegister?.toString() ?? '';
                _modbusShiftRegController.text =
                    preset.heatingCurveShiftRegister?.toString() ?? '';
                _modbusMultiplier = preset.multiplier;
                _modbusIsHolding = preset.isHoldingRegister;
              });
            },
          ),
          const SizedBox(height: 14),

          // ── Host, Port & Unit ID ─────────────────────────────
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _modbusHostController,
                  keyboardType: TextInputType.text,
                  decoration: _decoration(
                    label: 'Host / IP-Adresse',
                    icon: Icons.lan_outlined,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _modbusPortController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'Port',
                    icon: Icons.numbers_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _modbusUnitIdController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'Unit ID',
                    icon: Icons.tag_rounded,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Register Addresses Grid ──────────────────────────
          const Text(
            'Modbus Register-Adressen',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFECECF0),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _modbusOutdoorRegController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'Außentemperatur',
                    icon: Icons.thermostat_outlined,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _modbusFlowRegController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'Vorlauftemperatur',
                    icon: Icons.waves_rounded,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _modbusReturnRegController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'Rücklauftemperatur',
                    icon: Icons.rotate_left_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _modbusHwRegController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'Warmwasserspeicher',
                    icon: Icons.water_drop_outlined,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _modbusRoomRegController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'Raum-Soll (optional)',
                    icon: Icons.home_outlined,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _modbusShiftRegController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'Verschiebung (opt.)',
                    icon: Icons.tune_outlined,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Multiplier & Type ────────────────────────────────
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<double>(
                  initialValue: _modbusMultiplier,
                  decoration: _decoration(
                    label: 'Skalierungsfaktor',
                    icon: Icons.scale_outlined,
                  ),
                  dropdownColor: const Color(0xFF2A2A32),
                  items: const [
                    DropdownMenuItem(
                      value: 0.1,
                      child: Text('× 0.1 (°C, z.B. 215 = 21.5°C)',
                          style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: 0.01,
                      child: Text('× 0.01 (z.B. 2150 = 21.5°C)',
                          style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: 1.0,
                      child: Text('× 1.0 (z.B. 21 = 21°C)',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _modbusMultiplier = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<bool>(
                  initialValue: _modbusIsHolding,
                  decoration: _decoration(
                    label: 'Registertyp',
                    icon: Icons.memory_outlined,
                  ),
                  dropdownColor: const Color(0xFF2A2A32),
                  items: const [
                    DropdownMenuItem(
                      value: true,
                      child: Text('Holding (FC 03)',
                          style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: false,
                      child: Text('Input (FC 04)',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _modbusIsHolding = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Test & Connect Row ───────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testingModbus ? null : _testGenericModbusConnection,
                  icon: _testingModbus
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent,
                          ),
                        )
                      : const Icon(Icons.network_check_rounded, size: 18),
                  label: const Text('Verbindung testen'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: const BorderSide(color: accent),
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!provider.isConnected)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      final host = _modbusHostController.text.trim();
                      final port =
                          int.tryParse(_modbusPortController.text.trim());
                      if (host.isNotEmpty) {
                        provider.connectToIp(host, port: port);
                      }
                    },
                    icon: const Icon(Icons.power_rounded, size: 18),
                    label: const Text('Jetzt verbinden'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrunataCredentialsFields() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF24242C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_person_outlined,
                  color: Color(0xFFFFA726), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Brunata Portal-Zugang',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFECECF0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Verschlüsselt lokal gespeichert für den monatlichen Abrechnungsabruf.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
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
            validator: (v) {
              final p = context.read<ECLProvider>();
              if (p.selectedBillingId == 'brunata_hamburg') {
                if (v == null || v.trim().isEmpty) {
                  return 'Bitte Kundennummer eingeben';
                }
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
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
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) {
              final p = context.read<ECLProvider>();
              if (p.selectedBillingId == 'brunata_hamburg') {
                if (v == null || v.isEmpty) {
                  return 'Bitte Kennwort eingeben';
                }
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSimulatedBillingNotice(BillingProviderDescriptor desc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2836),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C4C64)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Color(0xFF38BDF8), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${desc.name} (Simulationsmodus)',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFECECF0),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Dieser Dienst befindet sich in Vorbereitung. Im aktuellen '
                  'Zustand emuliert der Heizungstrainer realistische Verbrauchs- '
                  'und Liegenschaftsdaten für den Community-Vergleich.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatabaseTile(ECLProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF24242C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A44)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B3D2F),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.cloud_done_rounded,
                    color: Color(0xFF4ADE80), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Lokale SQLite-Telemetriedatenbank',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFECECF0),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Alle 30s gepuffert. Trendanalysen sind permanent verfügbar.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF3A3A44), height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Offline-Puffer erzwingen',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFFECECF0),
              ),
            ),
            subtitle: Text(
              'Zeigt ausschließlich gespeicherte Messwerte an und pausiert Netzwerkabfragen.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            value: provider.isOfflineMode,
            activeThumbColor: const Color(0xFFFFA726),
            onChanged: (val) {
              if (val) {
                provider.openOfflineMode();
              } else {
                provider.exitOfflineMode();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTariffCard(ECLProvider provider) {
    final currentCarrier = _selectedCarrierId != null
        ? EnergyPriceService.getCarrierById(_selectedCarrierId!)
        : EnergyPriceService.knownCarriers.first;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF24242C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status & Dynamic Sync Row ───────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isCustomPrice
                        ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                        : const Color(0xFFFFA726).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isCustomPrice
                          ? const Color(0xFF38BDF8).withValues(alpha: 0.4)
                          : const Color(0xFFFFA726).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isCustomPrice
                            ? Icons.edit_note_rounded
                            : Icons.auto_graph_rounded,
                        size: 16,
                        color: _isCustomPrice
                            ? const Color(0xFF38BDF8)
                            : const Color(0xFFFFA726),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _isCustomPrice
                              ? 'Manueller Vertragspreis'
                              : 'Markt-Benchmark aktiv',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _isCustomPrice
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFFFFA726),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _fetchingMarketPrice
                    ? null
                    : () => _fetchDynamicMarketPrice(provider),
                icon: _fetchingMarketPrice
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFFFA726),
                        ),
                      )
                    : const Icon(Icons.sync_rounded, size: 16),
                label: const Text('Marktpreis abrufen',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFFA726),
                  side: const BorderSide(color: Color(0xFFFFA726)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Quick-Select Chips ─────────────────────────────
          const Text(
            'Energieträger & Benchmark (2026)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFECECF0),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Wähle einen Referenz-Benchmark für deinen Energieträger oder überschreibe ihn frei.',
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: EnergyPriceService.knownCarriers.map((carrier) {
              final isSelected =
                  _selectedCarrierId == carrier.id && !_isCustomPrice;
              return ChoiceChip(
                label: Text(
                  '${carrier.name} (${_formatPrice(carrier.benchmarkPricePerKwh)} €)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.black : const Color(0xFFECECF0),
                  ),
                ),
                selected: isSelected,
                selectedColor: const Color(0xFFFFA726),
                backgroundColor: const Color(0xFF2A2A32),
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFFFFA726)
                      : const Color(0xFF3A3A44),
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedCarrierId = carrier.id;
                      _priceController.text =
                          _formatPrice(carrier.benchmarkPricePerKwh);
                      _isCustomPrice = false;
                    });
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // ── Selected Benchmark Detail ─────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2028),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2E303C)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: Color(0xFF9E9EA8), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentCarrier.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFECECF0),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Quelle: ${currentCarrier.source}',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Text Input for Overwrite ───────────────────────
          TextFormField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: _decoration(
              label: 'Arbeitspreis pro kWh (manuell anpassbar)',
              icon: Icons.sell_outlined,
              suffixText: '€/kWh',
              helperText:
                  'Frei anpassbar. Ein manueller Eintrag überschreibt den Benchmark.',
            ),
            onChanged: (val) {
              final parsed = _parsePrice(val);
              setState(() {
                if (parsed == null ||
                    (parsed - currentCarrier.benchmarkPricePerKwh).abs() >
                        0.0001) {
                  _isCustomPrice = true;
                } else {
                  _isCustomPrice = false;
                }
              });
            },
            validator: (v) {
              final p = _parsePrice(v ?? '');
              if (p == null) return 'Bitte gültigen Preis eingeben';
              if (p <= 0 || p > 5) {
                return 'Preis muss zwischen 0 und 5 € liegen';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),

          // ── Tip Pill ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded,
                    color: Color(0xFFFFA726), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tipp: Den genauen Arbeitspreis entnimmst du deiner letzten Abrechnung.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.65),
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

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    Widget? suffix,
    String? suffixText,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
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

/// Header banner displaying currently active hardware and billing configuration.
class _ActiveSystemSummary extends StatelessWidget {
  final ECLProvider provider;

  const _ActiveSystemSummary({required this.provider});

  @override
  Widget build(BuildContext context) {
    final controllerDesc = provider.currentControllerDescriptor;
    final billingDesc = provider.currentBillingDescriptor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2C251C), Color(0xFF1E1E26)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFA726).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_rounded, color: Color(0xFFFFA726), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Aktives Setup',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Color(0xFFFFA726),
                ),
              ),
              const Spacer(),
              _ConnectionStatusBadge(provider: provider),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryBox(
                  icon: controllerDesc.icon,
                  label: 'Heizung',
                  value: controllerDesc.brand,
                  subtitle: controllerDesc.model,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryBox(
                  icon: billingDesc.icon,
                  label: 'Abrechnung',
                  value: billingDesc.name,
                  subtitle: provider.isSimulatedBilling ? 'Simulation' : 'Portal',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;

  const _SummaryBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFFFFA726)),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFFECECF0),
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatusBadge extends StatelessWidget {
  final ECLProvider provider;

  const _ConnectionStatusBadge({required this.provider});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String text;

    if (provider.isConnected) {
      bg = const Color(0xFF1B3D2F);
      fg = const Color(0xFF4ADE80);
      text = provider.isSimulatedController ? 'Simulation' : 'Verbunden';
    } else if (provider.isReconnecting) {
      bg = const Color(0xFF3D2E14);
      fg = const Color(0xFFFFB74D);
      text = 'Reconnecting';
    } else {
      bg = const Color(0xFF2C2C36);
      fg = const Color(0xFF9E9EA8);
      text = 'Getrennt';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// Interactive card for selecting or simulating a heating controller.
class _ControllerCard extends StatelessWidget {
  final ControllerDescriptor descriptor;
  final bool isSelected;
  final bool isConnected;
  final bool isConnecting;
  final VoidCallback onSelect;
  final VoidCallback onStartSimulation;
  final VoidCallback onDisconnect;

  const _ControllerCard({
    required this.descriptor,
    required this.isSelected,
    required this.isConnected,
    required this.isConnecting,
    required this.onSelect,
    required this.onStartSimulation,
    required this.onDisconnect,
  });

  String _protocolString(ConnectionProtocol protocol) {
    switch (protocol) {
      case ConnectionProtocol.modbusTcp:
        return 'Modbus TCP';
      case ConnectionProtocol.modbusRtu:
        return 'Modbus RTU';
      case ConnectionProtocol.restApi:
        return 'REST API';
      case ConnectionProtocol.mqtt:
        return 'MQTT';
      case ConnectionProtocol.eBus:
        return 'eBus';
      case ConnectionProtocol.proprietary:
        return 'Proprietär';
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFA726);

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2B251D) : const Color(0xFF24242C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accent : const Color(0xFF3A3A44),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accent.withValues(alpha: 0.18)
                        : const Color(0xFF2E2E38),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    descriptor.icon,
                    color: isSelected ? accent : const Color(0xFFB0B0BC),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            descriptor.brand,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? accent : const Color(0xFF9E9EA8),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _Badge(
                            text: descriptor.isSupported
                                ? 'Hardware'
                                : 'Simulation',
                            color: descriptor.isSupported
                                ? const Color(0xFF4ADE80)
                                : const Color(0xFFFFB74D),
                            bgColor: descriptor.isSupported
                                ? const Color(0xFF1B3D2F)
                                : const Color(0xFF3D2E14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        descriptor.model,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFECECF0),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected ? accent : const Color(0xFF6B6B78),
                  size: 22,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              descriptor.description,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _TagChip(label: _protocolString(descriptor.protocol)),
                const Spacer(),
                if (isSelected && !descriptor.isSupported) ...[
                  if (isConnected) ...[
                    OutlinedButton.icon(
                      onPressed: onDisconnect,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF8A80),
                        side: const BorderSide(color: Color(0xFF7F2C2C)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.stop_rounded, size: 16),
                      label: const Text('Trennen',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ] else ...[
                    FilledButton.tonalIcon(
                      onPressed: isConnecting ? null : onStartSimulation,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent.withValues(alpha: 0.2),
                        foregroundColor: accent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: isConnecting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow_rounded, size: 16),
                      label: Text(
                        isConnecting ? 'Startet...' : 'Simulation testen',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Interactive card for selecting or simulating a billing provider.
class _BillingProviderCard extends StatelessWidget {
  final BillingProviderDescriptor descriptor;
  final bool isSelected;
  final VoidCallback onSelect;

  const _BillingProviderCard({
    required this.descriptor,
    required this.isSelected,
    required this.onSelect,
  });

  String _authTypeString(BillingAuthType authType) {
    switch (authType) {
      case BillingAuthType.portalScraper:
        return 'Web-Portal';
      case BillingAuthType.restApi:
        return 'REST API';
      case BillingAuthType.oauth2:
        return 'OAuth 2.0';
      case BillingAuthType.fileImport:
        return 'Datei-Import';
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFA726);

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2B251D) : const Color(0xFF24242C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accent : const Color(0xFF3A3A44),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accent.withValues(alpha: 0.18)
                        : const Color(0xFF2E2E38),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    descriptor.icon,
                    color: isSelected ? accent : const Color(0xFFB0B0BC),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              descriptor.organization,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? accent
                                    : const Color(0xFF9E9EA8),
                              ),
                            ),
                          ),
                          _Badge(
                            text: descriptor.isSupported
                                ? 'Live'
                                : 'Simulation',
                            color: descriptor.isSupported
                                ? const Color(0xFF4ADE80)
                                : const Color(0xFF38BDF8),
                            bgColor: descriptor.isSupported
                                ? const Color(0xFF1B3D2F)
                                : const Color(0xFF163238),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        descriptor.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFECECF0),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected ? accent : const Color(0xFF6B6B78),
                  size: 22,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              descriptor.description,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 10),
            _TagChip(label: _authTypeString(descriptor.authType)),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;

  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF363642)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Color(0xFFB0B0BE),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final Color bgColor;

  const _Badge({
    required this.text,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
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
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
