import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/controllers/generic_modbus_controller.dart';
import 'package:heizungstrainer/controllers/bosch_buderus_ems_controller.dart';
import 'package:heizungstrainer/controllers/viessmann_controller.dart';
import 'package:heizungstrainer/controllers/vaillant_ebusd_controller.dart';
import 'package:heizungstrainer/controllers/weishaupt_wem_controller.dart';
import 'package:heizungstrainer/controllers/nibe_modbus_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/models/generic_modbus_config.dart';
import 'package:heizungstrainer/models/bosch_buderus_ems_config.dart';
import 'package:heizungstrainer/models/viessmann_config.dart';
import 'package:heizungstrainer/models/vaillant_ebusd_config.dart';
import 'package:heizungstrainer/models/weishaupt_wem_config.dart';
import 'package:heizungstrainer/models/nibe_modbus_config.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/log_screen.dart';
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
  final _portalUrlController = TextEditingController();
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
  final _modbusPollingIntervalController = TextEditingController(text: '10');
  String _modbusPresetId = 'standard';
  double _modbusMultiplier = 0.1;
  bool _modbusIsHolding = true;
  ModbusWordOrder _modbusWordOrder = ModbusWordOrder.bigEndian;
  ModbusRegisterDataType _modbusDataType = ModbusRegisterDataType.int16;
  bool _testingModbus = false;

  final _emsHostController = TextEditingController();
  final _emsPortController = TextEditingController();
  final _emsTokenController = TextEditingController();
  final _emsGatewayPassController = TextEditingController();
  final _emsPrivatePassController = TextEditingController();
  final _emsKm200KeyController = TextEditingController();
  String _emsCircuit = 'hc1';
  bool _emsUseHttps = false;
  BoschGatewayType _emsGatewayType = BoschGatewayType.emsEsp;
  String _emsPresetId = 'standard';
  bool _obscureEmsToken = true;
  bool _obscureKm200Pass = true;
  bool _testingEms = false;
  bool _discoveringEms = false;

  final _viessmannHostController = TextEditingController();
  final _viessmannPortController = TextEditingController();
  final _viessmannTokenController = TextEditingController();
  final _viessmannInstallIdController = TextEditingController();
  ViessmannConnectionType _viessmannConnType = ViessmannConnectionType.optolinkTcp;
  String _viessmannCircuit = '0';
  int _viessmannCloudPollingInterval = 60;
  String _viessmannPresetId = 'optolink_vcontrold';
  bool _obscureViessmannToken = true;
  bool _testingViessmann = false;

  final _vaillantHostController = TextEditingController();
  final _vaillantPortController = TextEditingController();
  final _vaillantCircuitController = TextEditingController();
  final _vaillantTokenController = TextEditingController();
  String _vaillantPresetId = 'ebusd_http_json';
  bool _vaillantUseHttps = false;
  bool _obscureVaillantToken = true;
  bool _testingVaillant = false;

  final _weishauptHostController = TextEditingController();
  final _weishauptPortController = TextEditingController();
  final _weishauptUnitIdController = TextEditingController();
  final _weishauptOutdoorRegController = TextEditingController();
  final _weishauptFlowRegController = TextEditingController();
  final _weishauptReturnRegController = TextEditingController();
  final _weishauptHwRegController = TextEditingController();
  final _weishauptRoomRegController = TextEditingController();
  final _weishauptShiftRegController = TextEditingController();
  String _weishauptPresetId = 'wem_wwp_split';
  double _weishauptMultiplier = 0.1;
  bool _weishauptIsHolding = true;
  bool _testingWeishaupt = false;

  final _nibeHostController = TextEditingController();
  final _nibePortController = TextEditingController();
  final _nibeUnitIdController = TextEditingController();
  final _nibeOutdoorRegController = TextEditingController();
  final _nibeFlowRegController = TextEditingController();
  final _nibeReturnRegController = TextEditingController();
  final _nibeHwRegController = TextEditingController();
  final _nibeRoomRegController = TextEditingController();
  final _nibeShiftRegController = TextEditingController();
  String _nibePresetId = 'nibe_s_series';
  double _nibeMultiplier = 0.1;
  bool _nibeIsHolding = true;
  bool _testingNibe = false;
  bool _testingBilling = false;

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
      final username = await provider.getBillingUsername();
      final password = await provider.getBillingPassword();
      final portalUrl = await provider.getBillingPortalUrl();
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
      _modbusPollingIntervalController.text =
          modbusCfg.pollingIntervalSeconds.toString();
      _modbusPresetId = modbusCfg.presetId;
      _modbusMultiplier = modbusCfg.multiplier;
      _modbusIsHolding = modbusCfg.isHoldingRegister;
      _modbusWordOrder = modbusCfg.wordOrder;
      _modbusDataType = modbusCfg.dataType;

      final emsCfg = provider.boschBuderusConfig;
      _emsHostController.text = emsCfg.host;
      _emsPortController.text = emsCfg.port.toString();
      _emsTokenController.text = emsCfg.apiToken;
      _emsGatewayPassController.text = emsCfg.gatewayPassword;
      _emsPrivatePassController.text = emsCfg.privatePassword;
      _emsKm200KeyController.text = emsCfg.km200Key;
      _emsCircuit = emsCfg.circuit;
      _emsUseHttps = emsCfg.useHttps;
      _emsGatewayType = emsCfg.gatewayType;
      _emsPresetId = emsCfg.presetId;

      final vCfg = provider.viessmannConfig;
      _viessmannHostController.text = vCfg.host;
      _viessmannPortController.text = vCfg.port.toString();
      _viessmannTokenController.text = vCfg.apiToken;
      _viessmannInstallIdController.text = vCfg.installationId;
      _viessmannConnType = vCfg.connectionType;
      _viessmannCircuit = vCfg.circuit;
      _viessmannCloudPollingInterval = vCfg.cloudPollingIntervalSeconds;
      _viessmannPresetId = vCfg.presetId;

      final vaillantCfg = provider.vaillantConfig;
      _vaillantHostController.text = vaillantCfg.host;
      _vaillantPortController.text = vaillantCfg.port.toString();
      _vaillantCircuitController.text = vaillantCfg.circuit;
      _vaillantTokenController.text = vaillantCfg.apiToken;
      _vaillantPresetId = vaillantCfg.presetId;
      _vaillantUseHttps = vaillantCfg.useHttps;

      final weishauptCfg = provider.weishauptConfig;
      _weishauptHostController.text = weishauptCfg.host;
      _weishauptPortController.text = weishauptCfg.port.toString();
      _weishauptUnitIdController.text = weishauptCfg.unitId.toString();
      _weishauptOutdoorRegController.text = weishauptCfg.outdoorRegister.toString();
      _weishauptFlowRegController.text = weishauptCfg.flowRegister.toString();
      _weishauptReturnRegController.text = weishauptCfg.returnRegister.toString();
      _weishauptHwRegController.text = weishauptCfg.hotWaterRegister.toString();
      _weishauptRoomRegController.text =
          weishauptCfg.roomTargetRegister?.toString() ?? '';
      _weishauptShiftRegController.text =
          weishauptCfg.heatingCurveShiftRegister?.toString() ?? '';
      _weishauptPresetId = weishauptCfg.presetId;
      _weishauptMultiplier = weishauptCfg.multiplier;
      _weishauptIsHolding = weishauptCfg.isHoldingRegister;

      final nibeCfg = provider.nibeConfig;
      _nibeHostController.text = nibeCfg.host;
      _nibePortController.text = nibeCfg.port.toString();
      _nibeUnitIdController.text = nibeCfg.unitId.toString();
      _nibeOutdoorRegController.text = nibeCfg.outdoorRegister.toString();
      _nibeFlowRegController.text = nibeCfg.flowRegister.toString();
      _nibeReturnRegController.text = nibeCfg.returnRegister.toString();
      _nibeHwRegController.text = nibeCfg.hotWaterRegister.toString();
      _nibeRoomRegController.text =
          nibeCfg.roomTargetRegister?.toString() ?? '';
      _nibeShiftRegController.text =
          nibeCfg.heatingCurveShiftRegister?.toString() ?? '';
      _nibePresetId = nibeCfg.presetId;
      _nibeMultiplier = nibeCfg.multiplier;
      _nibeIsHolding = nibeCfg.isHoldingRegister;

      if (!mounted) return;
      setState(() {
        _usernameController.text = username ?? '';
        _passwordController.text = password ?? '';
        _portalUrlController.text = portalUrl;
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
    _portalUrlController.dispose();
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
    _modbusPollingIntervalController.dispose();
    _emsHostController.dispose();
    _emsPortController.dispose();
    _emsTokenController.dispose();
    _emsGatewayPassController.dispose();
    _emsPrivatePassController.dispose();
    _emsKm200KeyController.dispose();
    _viessmannHostController.dispose();
    _viessmannPortController.dispose();
    _viessmannTokenController.dispose();
    _viessmannInstallIdController.dispose();
    _vaillantHostController.dispose();
    _vaillantPortController.dispose();
    _vaillantCircuitController.dispose();
    _vaillantTokenController.dispose();
    _weishauptHostController.dispose();
    _weishauptPortController.dispose();
    _weishauptUnitIdController.dispose();
    _weishauptOutdoorRegController.dispose();
    _weishauptFlowRegController.dispose();
    _weishauptReturnRegController.dispose();
    _weishauptHwRegController.dispose();
    _weishauptRoomRegController.dispose();
    _weishauptShiftRegController.dispose();
    _nibeHostController.dispose();
    _nibePortController.dispose();
    _nibeUnitIdController.dispose();
    _nibeOutdoorRegController.dispose();
    _nibeFlowRegController.dispose();
    _nibeReturnRegController.dispose();
    _nibeHwRegController.dispose();
    _nibeRoomRegController.dispose();
    _nibeShiftRegController.dispose();
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
      wordOrder: _modbusWordOrder,
      dataType: _modbusDataType,
      pollingIntervalSeconds:
          int.tryParse(_modbusPollingIntervalController.text.trim()) ?? 10,
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

  Future<void> _testBoschBuderusConnection() async {
    setState(() => _testingEms = true);
    final emsCfg = BoschBuderusEmsConfig(
      host: _emsHostController.text.trim().isEmpty
          ? '192.168.1.120'
          : _emsHostController.text.trim(),
      port: int.tryParse(_emsPortController.text.trim()) ?? 80,
      apiToken: _emsTokenController.text.trim(),
      circuit: _emsCircuit,
      useHttps: _emsUseHttps,
      gatewayType: _emsGatewayType,
      gatewayPassword: _emsGatewayPassController.text.trim(),
      privatePassword: _emsPrivatePassController.text.trim(),
      km200Key: _emsKm200KeyController.text.trim(),
      presetId: _emsPresetId,
    );

    final res = await BoschBuderusEmsController.testConnection(emsCfg);
    if (!mounted) return;
    setState(() => _testingEms = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${res['message'] ?? "Test erfolgreich!"}\n'
            'Vorlauf: ${res['flowTemp'] != null ? "${res['flowTemp']} °C" : "-"} | '
            'Rücklauf: ${res['returnTemp'] != null ? "${res['returnTemp']} °C" : "-"} | '
            'Außen: ${res['outdoorTemp'] != null ? "${res['outdoorTemp']} °C" : "-"} | '
            'WW: ${res['hotWaterTemp'] != null ? "${res['hotWaterTemp']} °C" : "-"}',
          ),
          backgroundColor: const Color(0xFF1B3D2F),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bosch/Buderus Verbindung fehlgeschlagen: ${res['message']}'),
          backgroundColor: const Color(0xFF5C1D1D),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _discoverEmsGateways() async {
    setState(() => _discoveringEms = true);
    try {
      final gateways = await BoschBuderusEmsController.discoverEmsGateways();
      if (!mounted) return;
      if (gateways.isNotEmpty) {
        final gw = gateways.first;
        setState(() {
          _emsHostController.text = gw.ip;
          _emsPortController.text = gw.port.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${gw.model} gefunden unter ${gw.ip} (${gw.version})!'),
            backgroundColor: const Color(0xFF1B3D2F),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kein EMS-ESP Gateway über mDNS gefunden. Bitte IP manuell eintragen.'),
            backgroundColor: Color(0xFF3A3A44),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler bei der Gateway-Suche: $e'),
          backgroundColor: const Color(0xFF5C1D1D),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _discoveringEms = false);
    }
  }

  Future<void> _testViessmannConnection() async {
    setState(() => _testingViessmann = true);
    final vCfg = ViessmannConfig(
      connectionType: _viessmannConnType,
      host: _viessmannHostController.text.trim().isEmpty
          ? '192.168.1.130'
          : _viessmannHostController.text.trim(),
      port: int.tryParse(_viessmannPortController.text.trim()) ??
          (_viessmannConnType == ViessmannConnectionType.optolinkTcp ? 3002 : 443),
      apiToken: _viessmannTokenController.text.trim(),
      installationId: _viessmannInstallIdController.text.trim(),
      circuit: _viessmannCircuit,
      cloudPollingIntervalSeconds: _viessmannCloudPollingInterval,
      presetId: _viessmannPresetId,
    );

    final res = await ViessmannController.testConnection(vCfg);
    if (!mounted) return;
    setState(() => _testingViessmann = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${res['message']}\n'
            'Typ: ${res['type']}\n'
            'Vorlauf: ${res['flowTemp'] != null ? "${res['flowTemp']} °C" : "-"} | '
            'Rücklauf: ${res['returnTemp'] != null ? "${res['returnTemp']} °C" : "-"} | '
            'Außen: ${res['outdoorTemp'] != null ? "${res['outdoorTemp']} °C" : "-"} | '
            'WW: ${res['hotWaterTemp'] != null ? "${res['hotWaterTemp']} °C" : "-"}',
          ),
          backgroundColor: const Color(0xFF1B3D2F),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${res['message']}'),
          backgroundColor: const Color(0xFF5C1D1D),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _testVaillantConnection() async {
    setState(() => _testingVaillant = true);
    final vaillantCfg = VaillantEbusdConfig(
      host: _vaillantHostController.text.trim().isEmpty
          ? '192.168.1.140'
          : _vaillantHostController.text.trim(),
      port: int.tryParse(_vaillantPortController.text.trim()) ?? 8889,
      circuit: _vaillantCircuitController.text.trim().isEmpty
          ? 'bai'
          : _vaillantCircuitController.text.trim(),
      apiToken: _vaillantTokenController.text.trim(),
      useHttps: _vaillantUseHttps,
      presetId: _vaillantPresetId,
    );

    final res = await VaillantEbusdController.testConnection(vaillantCfg);
    if (!mounted) return;
    setState(() => _testingVaillant = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'eBUSd Test erfolgreich!\n'
            'Vorlauf: ${res['flowTemp'] != null ? "${res['flowTemp']} °C" : "-"} | '
            'Rücklauf: ${res['returnTemp'] != null ? "${res['returnTemp']} °C" : "-"} | '
            'Außen: ${res['outdoorTemp'] != null ? "${res['outdoorTemp']} °C" : "-"} | '
            'WW: ${res['hotWaterTemp'] != null ? "${res['hotWaterTemp']} °C" : "-"}',
          ),
          backgroundColor: const Color(0xFF1B3D2F),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('eBUSd Verbindung fehlgeschlagen: ${res['message']}'),
          backgroundColor: const Color(0xFF5C1D1D),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _testWeishauptConnection() async {
    setState(() => _testingWeishaupt = true);
    final weishauptCfg = WeishauptWemConfig(
      host: _weishauptHostController.text.trim().isEmpty
          ? '192.168.1.150'
          : _weishauptHostController.text.trim(),
      port: int.tryParse(_weishauptPortController.text.trim()) ?? 502,
      unitId: int.tryParse(_weishauptUnitIdController.text.trim()) ?? 1,
      outdoorRegister: int.tryParse(_weishauptOutdoorRegController.text.trim()) ?? 3101,
      flowRegister: int.tryParse(_weishauptFlowRegController.text.trim()) ?? 3102,
      returnRegister: int.tryParse(_weishauptReturnRegController.text.trim()) ?? 3103,
      hotWaterRegister: int.tryParse(_weishauptHwRegController.text.trim()) ?? 3104,
      roomTargetRegister: int.tryParse(_weishauptRoomRegController.text.trim()),
      heatingCurveShiftRegister: int.tryParse(_weishauptShiftRegController.text.trim()),
      multiplier: _weishauptMultiplier,
      isHoldingRegister: _weishauptIsHolding,
      presetId: _weishauptPresetId,
    );

    final res = await WeishauptWemController.testConnection(weishauptCfg);
    if (!mounted) return;
    setState(() => _testingWeishaupt = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Weishaupt WEM Verbindungstest erfolgreich!\n'
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
          content: Text('Weishaupt Verbindung fehlgeschlagen: ${res['error']}'),
          backgroundColor: const Color(0xFF5C1D1D),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _testNibeConnection() async {
    setState(() => _testingNibe = true);
    final nibeCfg = NibeModbusConfig(
      host: _nibeHostController.text.trim().isEmpty
          ? '192.168.1.160'
          : _nibeHostController.text.trim(),
      port: int.tryParse(_nibePortController.text.trim()) ?? 502,
      unitId: int.tryParse(_nibeUnitIdController.text.trim()) ?? 1,
      outdoorRegister: int.tryParse(_nibeOutdoorRegController.text.trim()) ?? 1,
      flowRegister: int.tryParse(_nibeFlowRegController.text.trim()) ?? 5,
      returnRegister: int.tryParse(_nibeReturnRegController.text.trim()) ?? 7,
      hotWaterRegister: int.tryParse(_nibeHwRegController.text.trim()) ?? 8,
      roomTargetRegister: int.tryParse(_nibeRoomRegController.text.trim()),
      heatingCurveShiftRegister: int.tryParse(_nibeShiftRegController.text.trim()),
      multiplier: _nibeMultiplier,
      isHoldingRegister: _nibeIsHolding,
      presetId: _nibePresetId,
    );

    final res = await NibeModbusController.testConnection(nibeCfg);
    if (!mounted) return;
    setState(() => _testingNibe = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'NIBE Verbindungstest erfolgreich!\n'
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
          content: Text('NIBE Verbindung fehlgeschlagen: ${res['error']}'),
          backgroundColor: const Color(0xFF5C1D1D),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _testBillingConnection() async {
    setState(() => _testingBilling = true);
    final provider = context.read<ECLProvider>();
    await provider.saveBillingSettings(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      pricePerKwh: _parsePrice(_priceController.text) ?? 0.128,
      carrierId: _selectedCarrierId,
      portalUrl: _portalUrlController.text.trim(),
      isCustom: _isCustomPrice,
      syncAfterSave: false,
    );
    await provider.syncBillingData();
    if (!mounted) return;
    setState(() => _testingBilling = false);

    if (provider.brunataSyncError == null && provider.brunataData != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${provider.currentBillingDescriptor.name} Synchronisation erfolgreich!\n'
            'Verbrauch: ${provider.brunataData!.consumedKwh.toStringAsFixed(0)} kWh | '
            'Kosten: ${provider.brunataData!.currentBillingPeriodCost.toStringAsFixed(2)} € | '
            'Gebäudevergleich: ${provider.brunataData!.communityComparisonPercentage > 0 ? "+" : ""}${provider.brunataData!.communityComparisonPercentage.toStringAsFixed(1)}%',
          ),
          backgroundColor: const Color(0xFF1B3D2F),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fehler bei Synchronisation: ${provider.brunataSyncError ?? "Unbekannter Fehler"}',
          ),
          backgroundColor: const Color(0xFF5C1D1D),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
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
        wordOrder: _modbusWordOrder,
        dataType: _modbusDataType,
        pollingIntervalSeconds:
            int.tryParse(_modbusPollingIntervalController.text.trim()) ?? 10,
        presetId: _modbusPresetId,
        presetName: GenericModbusConfig.presets
            .firstWhere((p) => p.id == _modbusPresetId,
                orElse: () => GenericModbusConfig.presets.first)
            .name,
      );
      await provider.updateGenericModbusConfig(modbusCfg);
    }

    if (provider.selectedControllerId == 'bosch_buderus_ems') {
      final emsCfg = BoschBuderusEmsConfig(
        host: _emsHostController.text.trim().isEmpty
            ? '192.168.1.120'
            : _emsHostController.text.trim(),
        port: int.tryParse(_emsPortController.text.trim()) ?? 80,
        apiToken: _emsTokenController.text.trim(),
        circuit: _emsCircuit,
        useHttps: _emsUseHttps,
        gatewayType: _emsGatewayType,
        gatewayPassword: _emsGatewayPassController.text.trim(),
        privatePassword: _emsPrivatePassController.text.trim(),
        km200Key: _emsKm200KeyController.text.trim(),
        presetId: _emsPresetId,
        presetName: BoschBuderusEmsConfig.presets
            .firstWhere((p) => p.id == _emsPresetId,
                orElse: () => BoschBuderusEmsConfig.presets.first)
            .name,
      );
      await provider.updateBoschBuderusConfig(emsCfg);
    }

    if (provider.selectedControllerId == 'viessmann_vicare') {
      final vCfg = ViessmannConfig(
        connectionType: _viessmannConnType,
        host: _viessmannHostController.text.trim().isEmpty
            ? '192.168.1.130'
            : _viessmannHostController.text.trim(),
        port: int.tryParse(_viessmannPortController.text.trim()) ??
            (_viessmannConnType == ViessmannConnectionType.optolinkTcp ? 3002 : 443),
        apiToken: _viessmannTokenController.text.trim(),
        installationId: _viessmannInstallIdController.text.trim(),
        circuit: _viessmannCircuit,
        cloudPollingIntervalSeconds: _viessmannCloudPollingInterval,
        presetId: _viessmannPresetId,
        presetName: ViessmannConfig.presets
            .firstWhere((p) => p.id == _viessmannPresetId,
                orElse: () => ViessmannConfig.presets.first)
            .name,
      );
      await provider.updateViessmannConfig(vCfg);
    }

    if (provider.selectedControllerId == 'vaillant_ebusd') {
      final vaillantCfg = VaillantEbusdConfig(
        host: _vaillantHostController.text.trim().isEmpty
            ? '192.168.1.140'
            : _vaillantHostController.text.trim(),
        port: int.tryParse(_vaillantPortController.text.trim()) ?? 8889,
        circuit: _vaillantCircuitController.text.trim().isEmpty
            ? 'bai'
            : _vaillantCircuitController.text.trim(),
        apiToken: _vaillantTokenController.text.trim(),
        useHttps: _vaillantUseHttps,
        presetId: _vaillantPresetId,
        presetName: VaillantEbusdConfig.presets
            .firstWhere((p) => p.id == _vaillantPresetId,
                orElse: () => VaillantEbusdConfig.presets.first)
            .name,
      );
      await provider.updateVaillantConfig(vaillantCfg);
    }

    if (provider.selectedControllerId == 'weishaupt_wem') {
      final weishauptCfg = WeishauptWemConfig(
        host: _weishauptHostController.text.trim().isEmpty
            ? '192.168.1.150'
            : _weishauptHostController.text.trim(),
        port: int.tryParse(_weishauptPortController.text.trim()) ?? 502,
        unitId: int.tryParse(_weishauptUnitIdController.text.trim()) ?? 1,
        outdoorRegister:
            int.tryParse(_weishauptOutdoorRegController.text.trim()) ?? 3101,
        flowRegister:
            int.tryParse(_weishauptFlowRegController.text.trim()) ?? 3102,
        returnRegister:
            int.tryParse(_weishauptReturnRegController.text.trim()) ?? 3103,
        hotWaterRegister:
            int.tryParse(_weishauptHwRegController.text.trim()) ?? 3104,
        roomTargetRegister:
            int.tryParse(_weishauptRoomRegController.text.trim()),
        heatingCurveShiftRegister:
            int.tryParse(_weishauptShiftRegController.text.trim()),
        multiplier: _weishauptMultiplier,
        isHoldingRegister: _weishauptIsHolding,
        presetId: _weishauptPresetId,
        presetName: WeishauptWemConfig.presets
            .firstWhere((p) => p.id == _weishauptPresetId,
                orElse: () => WeishauptWemConfig.presets.first)
            .name,
      );
      await provider.updateWeishauptConfig(weishauptCfg);
    }

    if (provider.selectedControllerId == 'nibe_modbus') {
      final nibeCfg = NibeModbusConfig(
        host: _nibeHostController.text.trim().isEmpty
            ? '192.168.1.160'
            : _nibeHostController.text.trim(),
        port: int.tryParse(_nibePortController.text.trim()) ?? 502,
        unitId: int.tryParse(_nibeUnitIdController.text.trim()) ?? 1,
        outdoorRegister:
            int.tryParse(_nibeOutdoorRegController.text.trim()) ?? 1,
        flowRegister:
            int.tryParse(_nibeFlowRegController.text.trim()) ?? 5,
        returnRegister:
            int.tryParse(_nibeReturnRegController.text.trim()) ?? 7,
        hotWaterRegister:
            int.tryParse(_nibeHwRegController.text.trim()) ?? 8,
        roomTargetRegister:
            int.tryParse(_nibeRoomRegController.text.trim()),
        heatingCurveShiftRegister:
            int.tryParse(_nibeShiftRegController.text.trim()),
        multiplier: _nibeMultiplier,
        isHoldingRegister: _nibeIsHolding,
        presetId: _nibePresetId,
        presetName: NibeModbusConfig.presets
            .firstWhere((p) => p.id == _nibePresetId,
                orElse: () => NibeModbusConfig.presets.first)
            .name,
      );
      await provider.updateNibeConfig(nibeCfg);
    }

    await provider.saveBillingSettings(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      pricePerKwh: _parsePrice(_priceController.text)!,
      carrierId: _selectedCarrierId,
      portalUrl: _portalUrlController.text.trim(),
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
                      if (provider.selectedControllerId == 'bosch_buderus_ems') ...[
                        const SizedBox(height: 8),
                        _buildBoschBuderusConfigCard(provider),
                      ],
                      if (provider.selectedControllerId == 'viessmann_vicare') ...[
                        const SizedBox(height: 8),
                        _buildViessmannConfigCard(provider),
                      ],
                      if (provider.selectedControllerId == 'vaillant_ebusd') ...[
                        const SizedBox(height: 8),
                        _buildVaillantEbusdConfigCard(provider),
                      ],
                      if (provider.selectedControllerId == 'weishaupt_wem') ...[
                        const SizedBox(height: 8),
                        _buildWeishauptWemConfigCard(provider),
                      ],
                      if (provider.selectedControllerId == 'nibe_modbus') ...[
                        const SizedBox(height: 8),
                        _buildNibeModbusConfigCard(provider),
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
                          onSelect: () async {
                            await provider
                                .setSelectedBillingProvider(billingDesc.id);
                            final u = await provider.getBillingUsername();
                            final p = await provider.getBillingPassword();
                            final url = await provider.getBillingPortalUrl();
                            if (!mounted) return;
                            setState(() {
                              _usernameController.text = u ?? '';
                              _passwordController.text = p ?? '';
                              _portalUrlController.text = url;
                            });
                          },
                        );
                      }),
                      const SizedBox(height: 16),

                      _buildBillingCredentialsFields(provider),
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
                      const SizedBox(height: 12),
                      _buildDiagnosticLogsTile(provider),
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
                _modbusWordOrder = preset.wordOrder;
                _modbusDataType = preset.dataType;
                _modbusPollingIntervalController.text =
                    preset.pollingIntervalSeconds.toString();
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
          const SizedBox(height: 14),

          // ── Endianness & Data Type ───────────────────────────
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<ModbusWordOrder>(
                  initialValue: _modbusWordOrder,
                  decoration: _decoration(
                    label: 'Word- / Byte-Order',
                    icon: Icons.swap_horiz_rounded,
                  ),
                  dropdownColor: const Color(0xFF2A2A32),
                  items: const [
                    DropdownMenuItem(
                      value: ModbusWordOrder.bigEndian,
                      child: Text('Big-Endian (ABCD)',
                          style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: ModbusWordOrder.wordSwap,
                      child: Text('Word-Swap (CDAB, Luxtronik)',
                          style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: ModbusWordOrder.littleEndian,
                      child: Text('Little-Endian (DCBA)',
                          style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: ModbusWordOrder.byteSwap,
                      child: Text('Byte-Swap (BADC)',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _modbusWordOrder = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<ModbusRegisterDataType>(
                  initialValue: _modbusDataType,
                  decoration: _decoration(
                    label: 'Datentyp',
                    icon: Icons.data_object_rounded,
                  ),
                  dropdownColor: const Color(0xFF2A2A32),
                  items: const [
                    DropdownMenuItem(
                      value: ModbusRegisterDataType.int16,
                      child: Text('16-bit Int', style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: ModbusRegisterDataType.uint16,
                      child: Text('16-bit UInt', style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: ModbusRegisterDataType.int32,
                      child: Text('32-bit Int', style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: ModbusRegisterDataType.uint32,
                      child: Text('32-bit UInt', style: TextStyle(fontSize: 12)),
                    ),
                    DropdownMenuItem(
                      value: ModbusRegisterDataType.float32,
                      child: Text('32-bit Float', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _modbusDataType = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Polling Interval & Throttling ────────────────────
          TextFormField(
            controller: _modbusPollingIntervalController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _decoration(
              label: 'Abfrage-Intervall (Sekunden)',
              icon: Icons.timer_outlined,
            ).copyWith(
              helperText: _modbusPresetId == 'stiebel_isg'
                  ? 'ISG Throttling: Min. 5 Sek. empfohlen, um Abstürze des ISG-Webservers zu vermeiden.'
                  : 'Empfohlen: 5 bis 30 Sekunden.',
              helperStyle: TextStyle(
                fontSize: 11,
                color: _modbusPresetId == 'stiebel_isg'
                    ? const Color(0xFFFFA726)
                    : Colors.white.withValues(alpha: 0.4),
              ),
            ),
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

  Widget _buildBoschBuderusConfigCard(ECLProvider provider) {
    const accent = Color(0xFFEF5350);

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
              const Icon(Icons.fireplace_rounded,
                  color: accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Bosch / Buderus EMS-ESP Konfiguration',
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
            'Verbindung zum lokalen EMS-Bus REST-Gateway (z.B. BBQKees Gateway, Buderus Logamatic oder Bosch Condens).',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),

          // ── Preset Selector ──────────────────────────────────
          DropdownButtonFormField<String>(
            initialValue: _emsPresetId,
            decoration: _decoration(
              label: 'Gateway-Profil / Preset',
              icon: Icons.bookmarks_outlined,
            ),
            dropdownColor: const Color(0xFF2A2A32),
            items: BoschBuderusEmsConfig.presets.map((preset) {
              return DropdownMenuItem(
                value: preset.id,
                child: Text(preset.name, style: const TextStyle(fontSize: 13.5)),
              );
            }).toList(),
            onChanged: (id) {
              if (id == null) return;
              final preset =
                  BoschBuderusEmsConfig.presets.firstWhere((p) => p.id == id);
              setState(() {
                _emsPresetId = id;
                _emsPortController.text = preset.defaultPort.toString();
                _emsCircuit = preset.defaultCircuit;
                _emsUseHttps = preset.defaultUseHttps;
                _emsGatewayType = preset.defaultGatewayType;
              });
            },
          ),
          const SizedBox(height: 14),

          // ── Gateway-Typ Selector ─────────────────────────────
          DropdownButtonFormField<BoschGatewayType>(
            initialValue: _emsGatewayType,
            decoration: _decoration(
              label: 'Gateway-Typ & Protokoll',
              icon: Icons.device_hub_rounded,
            ),
            dropdownColor: const Color(0xFF2A2A32),
            items: const [
              DropdownMenuItem(
                value: BoschGatewayType.emsEsp,
                child: Text('EMS-ESP Gateway (BBQKees REST API v3)',
                    style: TextStyle(fontSize: 13)),
              ),
              DropdownMenuItem(
                value: BoschGatewayType.km200,
                child: Text('Buderus KM200 / MB LAN 2 / MX300 (AES-128 lokal)',
                    style: TextStyle(fontSize: 13)),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _emsGatewayType = val;
                  if (val == BoschGatewayType.km200 && _emsPortController.text == '80') {
                    _emsPortController.text = '80';
                  }
                });
              }
            },
          ),
          const SizedBox(height: 14),

          // ── Auto-Discovery (EMS-ESP) ──────────────────────────
          if (_emsGatewayType == BoschGatewayType.emsEsp) ...[
            OutlinedButton.icon(
              onPressed: _discoveringEms ? null : _discoverEmsGateways,
              icon: _discoveringEms
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                    )
                  : const Icon(Icons.radar_outlined, size: 16),
              label: Text(_discoveringEms
                  ? 'Suche EMS-ESP Gateways...'
                  : 'EMS-ESP Gateway im Heimnetz suchen (mDNS)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: const BorderSide(color: Color(0xFF4A2A2A)),
                minimumSize: const Size.fromHeight(38),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Host & Port ──────────────────────────────────────
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _emsHostController,
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
                  controller: _emsPortController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'Port',
                    icon: Icons.numbers_outlined,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Circuit & HTTPS (EMS-ESP) or Circuit & Info (KM200)
          if (_emsGatewayType == BoschGatewayType.emsEsp) ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: _emsCircuit,
                    decoration: _decoration(
                      label: 'Heizkreis (Circuit)',
                      icon: Icons.tune_rounded,
                    ),
                    dropdownColor: const Color(0xFF2A2A32),
                    items: const [
                      DropdownMenuItem(
                        value: 'hc1',
                        child: Text('Heizkreis 1 (hc1)', style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'hc2',
                        child: Text('Heizkreis 2 (hc2)', style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'hc3',
                        child: Text('Heizkreis 3 (hc3)', style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'hc4',
                        child: Text('Heizkreis 4 (hc4)', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _emsCircuit = val);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A32),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF3A3A44)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'HTTPS',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFECECF0),
                          ),
                        ),
                        Switch(
                          value: _emsUseHttps,
                          activeThumbColor: accent,
                          onChanged: (v) => setState(() => _emsUseHttps = v),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── API Token ────────────────────────────────────────
            TextFormField(
              controller: _emsTokenController,
              obscureText: _obscureEmsToken,
              decoration: _decoration(
                label: 'API Token / Bearer Token (Optional)',
                icon: Icons.key_rounded,
              ).copyWith(
                helperText: 'Optional: Nur notwendig, wenn im EMS-ESP Token-Authentifizierung aktiviert ist.',
                helperStyle: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureEmsToken ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: Colors.white54,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureEmsToken = !_obscureEmsToken),
                ),
              ),
            ),
          ] else ...[
            // ── KM200 / MB LAN ──────────────────────────────────
            DropdownButtonFormField<String>(
              initialValue: _emsCircuit,
              decoration: _decoration(
                label: 'Heizkreis (Circuit)',
                icon: Icons.tune_rounded,
              ),
              dropdownColor: const Color(0xFF2A2A32),
              items: const [
                DropdownMenuItem(
                  value: 'hc1',
                  child: Text('Heizkreis 1 (hc1)', style: TextStyle(fontSize: 13)),
                ),
                DropdownMenuItem(
                  value: 'hc2',
                  child: Text('Heizkreis 2 (hc2)', style: TextStyle(fontSize: 13)),
                ),
                DropdownMenuItem(
                  value: 'hc3',
                  child: Text('Heizkreis 3 (hc3)', style: TextStyle(fontSize: 13)),
                ),
                DropdownMenuItem(
                  value: 'hc4',
                  child: Text('Heizkreis 4 (hc4)', style: TextStyle(fontSize: 13)),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _emsCircuit = val);
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _emsGatewayPassController,
              obscureText: _obscureKm200Pass,
              decoration: _decoration(
                label: 'Gateway-Passwort (Geräteaufkleber)',
                icon: Icons.vpn_key_outlined,
              ).copyWith(
                helperText: 'Format z.B. xxxx-xxxx-xxxx-xxxx vom Aufkleber am Gateway/Kessel.',
                helperStyle: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureKm200Pass ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: Colors.white54,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureKm200Pass = !_obscureKm200Pass),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emsPrivatePassController,
              obscureText: _obscureKm200Pass,
              decoration: _decoration(
                label: 'Persönliches App-Passwort',
                icon: Icons.password_rounded,
              ).copyWith(
                helperText: 'Passwort aus der Buderus MyDevice / Bosch EasyControl App.',
                helperStyle: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emsKm200KeyController,
              obscureText: true,
              decoration: _decoration(
                label: 'Direkter AES-Schlüssel (32 Hex-Zeichen, optional)',
                icon: Icons.security_rounded,
              ).copyWith(
                helperText: 'Optional: Überschreibt die Passwort-Schlüsselableitung.',
                helperStyle: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E26),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF33333E)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_rounded, size: 16, color: Color(0xFF81C784)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Zero-Cloud: Der 128-Bit AES-Schlüssel wird lokal auf diesem Gerät generiert. Keine Daten verlassen dein Heimnetz.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // ── Test & Connect Row ───────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testingEms ? null : _testBoschBuderusConnection,
                  icon: _testingEms
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
                      final host = _emsHostController.text.trim();
                      final port = int.tryParse(_emsPortController.text.trim());
                      if (host.isNotEmpty) {
                        provider.connectToIp(host, port: port);
                      }
                    },
                    icon: const Icon(Icons.power_rounded, size: 18),
                    label: const Text('Jetzt verbinden'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
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

  Widget _buildViessmannConfigCard(ECLProvider provider) {
    const accent = Color(0xFFFF6D00);

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
              const Icon(Icons.heat_pump_rounded,
                  color: accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Viessmann Vitotronic & ViCare Konfiguration',
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
            'Verbindung über lokales Optolink (vcontrold / ESP-Optolink) oder die ViCare Cloud-API.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),

          // ── Preset Selector ──────────────────────────────────
          DropdownButtonFormField<String>(
            initialValue: _viessmannPresetId,
            decoration: _decoration(
              label: 'Viessmann Profil / Preset',
              icon: Icons.bookmarks_outlined,
            ),
            dropdownColor: const Color(0xFF2A2A32),
            items: ViessmannConfig.presets.map((preset) {
              return DropdownMenuItem(
                value: preset.id,
                child: Text(preset.name, style: const TextStyle(fontSize: 13.5)),
              );
            }).toList(),
            onChanged: (id) {
              if (id == null) return;
              final preset =
                  ViessmannConfig.presets.firstWhere((p) => p.id == id);
              setState(() {
                _viessmannPresetId = id;
                _viessmannConnType = preset.connectionType;
                _viessmannPortController.text = preset.defaultPort.toString();
                _viessmannCircuit = preset.defaultCircuit;
              });
            },
          ),
          const SizedBox(height: 14),

          // ── Connection Type Selector ─────────────────────────
          DropdownButtonFormField<ViessmannConnectionType>(
            initialValue: _viessmannConnType,
            decoration: _decoration(
              label: 'Verbindungsart',
              icon: Icons.hub_outlined,
            ),
            dropdownColor: const Color(0xFF2A2A32),
            items: const [
              DropdownMenuItem(
                value: ViessmannConnectionType.optolinkTcp,
                child: Text('Lokales Optolink (vcontrold / TCP)',
                    style: TextStyle(fontSize: 13)),
              ),
              DropdownMenuItem(
                value: ViessmannConnectionType.vicareRest,
                child: Text('Viessmann ViCare API (Cloud REST)',
                    style: TextStyle(fontSize: 13)),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _viessmannConnType = val;
                  if (val == ViessmannConnectionType.optolinkTcp &&
                      _viessmannPortController.text == '443') {
                    _viessmannPortController.text = '3002';
                  } else if (val == ViessmannConnectionType.vicareRest &&
                      _viessmannPortController.text == '3002') {
                    _viessmannPortController.text = '443';
                  }
                });
              }
            },
          ),
          const SizedBox(height: 14),

          // ── Mode-specific inputs ─────────────────────────────
          if (_viessmannConnType == ViessmannConnectionType.optolinkTcp) ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _viessmannHostController,
                    keyboardType: TextInputType.text,
                    decoration: _decoration(
                      label: 'vcontrold Host / IP',
                      icon: Icons.lan_outlined,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _viessmannPortController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _decoration(
                      label: 'TCP Port',
                      icon: Icons.numbers_outlined,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Standard-Port für vcontrold und Openv ist 3002 (ESP-Optolink: 3002 oder 7362).',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ] else ...[
            TextFormField(
              controller: _viessmannTokenController,
              obscureText: _obscureViessmannToken,
              decoration: _decoration(
                label: 'ViCare API Token / Personal Client Secret',
                icon: Icons.key_rounded,
              ).copyWith(
                helperText: 'Erstelle einen Personal API Key im Viessmann Developer Portal.',
                helperStyle: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureViessmannToken ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: Colors.white54,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureViessmannToken = !_obscureViessmannToken),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _viessmannInstallIdController,
              keyboardType: TextInputType.text,
              decoration: _decoration(
                label: 'Installations-ID (Optional)',
                icon: Icons.tag_rounded,
              ).copyWith(
                helperText: 'Leer lassen, um die erste gefundene Anlage automatisch zu nutzen.',
                helperStyle: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
              ),
            ),
          ],
          const SizedBox(height: 14),

          // ── Heating Circuit Selector ─────────────────────────
          DropdownButtonFormField<String>(
            initialValue: _viessmannCircuit,
            decoration: _decoration(
              label: 'Heizkreis (Circuit)',
              icon: Icons.tune_rounded,
            ),
            dropdownColor: const Color(0xFF2A2A32),
            items: const [
              DropdownMenuItem(
                value: '0',
                child: Text('Heizkreis 0 (A1 / HK1)', style: TextStyle(fontSize: 13)),
              ),
              DropdownMenuItem(
                value: '1',
                child: Text('Heizkreis 1 (M2 / HK2)', style: TextStyle(fontSize: 13)),
              ),
              DropdownMenuItem(
                value: '2',
                child: Text('Heizkreis 2 (M3 / HK3)', style: TextStyle(fontSize: 13)),
              ),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _viessmannCircuit = val);
            },
          ),
          if (_viessmannConnType == ViessmannConnectionType.vicareRest) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue: _viessmannCloudPollingInterval,
              decoration: _decoration(
                label: 'Cloud Abfrage-Intervall',
                icon: Icons.timer_outlined,
              ).copyWith(
                helperText:
                    'ViCare Cloud-Kontingent: Max. 1.450 Aufrufe/Tag. 60–120s schützt vor Sperren (HTTP 429).',
                helperStyle: const TextStyle(fontSize: 11, color: Color(0xFFFFB74D)),
                helperMaxLines: 2,
              ),
              dropdownColor: const Color(0xFF2A2A32),
              items: const [
                DropdownMenuItem(
                  value: 60,
                  child: Text('60 Sekunden (Empfohlen - ~1.440 Anfragen/Tag)',
                      style: TextStyle(fontSize: 12.5)),
                ),
                DropdownMenuItem(
                  value: 90,
                  child: Text('90 Sekunden (Sicher - ~960 Anfragen/Tag)',
                      style: TextStyle(fontSize: 12.5)),
                ),
                DropdownMenuItem(
                  value: 120,
                  child: Text('120 Sekunden (Sparsam - ~720 Anfragen/Tag)',
                      style: TextStyle(fontSize: 12.5)),
                ),
                DropdownMenuItem(
                  value: 180,
                  child: Text('180 Sekunden (Minimal - ~480 Anfragen/Tag)',
                      style: TextStyle(fontSize: 12.5)),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _viessmannCloudPollingInterval = val);
                }
              },
            ),
          ],
          const SizedBox(height: 16),

          // ── Test & Connect Row ───────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testingViessmann ? null : _testViessmannConnection,
                  icon: _testingViessmann
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
                      final host = _viessmannHostController.text.trim();
                      final port = int.tryParse(_viessmannPortController.text.trim());
                      if (host.isNotEmpty) {
                        provider.connectToIp(host, port: port);
                      }
                    },
                    icon: const Icon(Icons.power_rounded, size: 18),
                    label: const Text('Jetzt verbinden'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
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

  Widget _buildVaillantEbusdConfigCard(ECLProvider provider) {
    const accent = Color(0xFF00897B);

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
              const Icon(Icons.solar_power_rounded,
                  color: accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Vaillant eBUSd Gateway Konfiguration',
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
            'Verbindung zum lokalen eBUSd HTTP REST JSON Daemon (z.B. auf Raspberry Pi oder ESP32 eBUS-Adapter).',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),

          // ── Preset Selector ──────────────────────────────────
          DropdownButtonFormField<String>(
            initialValue: _vaillantPresetId,
            decoration: _decoration(
              label: 'Gateway-Profil / Preset',
              icon: Icons.bookmarks_outlined,
            ),
            dropdownColor: const Color(0xFF2A2A32),
            items: VaillantEbusdConfig.presets.map((preset) {
              return DropdownMenuItem(
                value: preset.id,
                child: Text(preset.name, style: const TextStyle(fontSize: 13.5)),
              );
            }).toList(),
            onChanged: (id) {
              if (id == null) return;
              final preset =
                  VaillantEbusdConfig.presets.firstWhere((p) => p.id == id);
              setState(() {
                _vaillantPresetId = id;
                _vaillantPortController.text = preset.defaultPort.toString();
                _vaillantCircuitController.text = preset.defaultCircuit;
                _vaillantUseHttps = preset.defaultUseHttps;
              });
            },
          ),
          const SizedBox(height: 14),

          // ── Host & Port ──────────────────────────────────────
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _vaillantHostController,
                  keyboardType: TextInputType.text,
                  decoration: _decoration(
                    label: 'eBUSd Host / IP',
                    icon: Icons.lan_outlined,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _vaillantPortController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'Port',
                    icon: Icons.numbers_outlined,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Circuit & HTTPS ──────────────────────────────────
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _vaillantCircuitController,
                  keyboardType: TextInputType.text,
                  decoration: _decoration(
                    label: 'Heizkreis / Modul',
                    icon: Icons.tune_rounded,
                  ).copyWith(
                    helperText: 'Standard: bai (Kessel) oder 700 / 720 (Regler)',
                    helperStyle: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A32),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF3A3A44)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'HTTPS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFECECF0),
                        ),
                      ),
                      Switch(
                        value: _vaillantUseHttps,
                        activeThumbColor: accent,
                        onChanged: (v) => setState(() => _vaillantUseHttps = v),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── API Token ────────────────────────────────────────
          TextFormField(
            controller: _vaillantTokenController,
            obscureText: _obscureVaillantToken,
            decoration: _decoration(
              label: 'API Token / Auth Header (Optional)',
              icon: Icons.key_rounded,
            ).copyWith(
              helperText: 'Optional: Nur notwendig bei vorgeschaltetem Auth-Proxy.',
              helperStyle: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureVaillantToken ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: Colors.white54,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureVaillantToken = !_obscureVaillantToken),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Test & Connect Row ───────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testingVaillant ? null : _testVaillantConnection,
                  icon: _testingVaillant
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
                      final host = _vaillantHostController.text.trim();
                      final port = int.tryParse(_vaillantPortController.text.trim());
                      if (host.isNotEmpty) {
                        provider.connectToIp(host, port: port);
                      }
                    },
                    icon: const Icon(Icons.power_rounded, size: 18),
                    label: const Text('Jetzt verbinden'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
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

  Widget _buildWeishauptWemConfigCard(ECLProvider provider) {
    const accent = Color(0xFF00ACC1);

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
              const Icon(Icons.hvac_rounded,
                  color: accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Weishaupt WEM Gateway Konfiguration',
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
            'Modbus-TCP-Anbindung für Weishaupt WWP LS / LB Split-Wärmepumpen, BiBlock und WTC-GW.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),

          // ── Preset Selector ──────────────────────────────────
          DropdownButtonFormField<String>(
            initialValue: _weishauptPresetId,
            decoration: _decoration(
              label: 'Weishaupt Modell / Preset',
              icon: Icons.bookmarks_outlined,
            ),
            dropdownColor: const Color(0xFF2A2A32),
            items: WeishauptWemConfig.presets.map((preset) {
              return DropdownMenuItem(
                value: preset.id,
                child: Text(preset.name, style: const TextStyle(fontSize: 13.5)),
              );
            }).toList(),
            onChanged: (id) {
              if (id == null) return;
              final preset =
                  WeishauptWemConfig.presets.firstWhere((p) => p.id == id);
              setState(() {
                _weishauptPresetId = id;
                _weishauptPortController.text = preset.defaultPort.toString();
                _weishauptUnitIdController.text = preset.defaultUnitId.toString();
                _weishauptOutdoorRegController.text = preset.outdoorRegister.toString();
                _weishauptFlowRegController.text = preset.flowRegister.toString();
                _weishauptReturnRegController.text = preset.returnRegister.toString();
                _weishauptHwRegController.text = preset.hotWaterRegister.toString();
                _weishauptRoomRegController.text =
                    preset.roomTargetRegister?.toString() ?? '';
                _weishauptShiftRegController.text =
                    preset.heatingCurveShiftRegister?.toString() ?? '';
                _weishauptMultiplier = preset.multiplier;
                _weishauptIsHolding = preset.isHoldingRegister;
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
                  controller: _weishauptHostController,
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
                  controller: _weishauptPortController,
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
                  controller: _weishauptUnitIdController,
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
            'Weishaupt Modbus Register-Adressen',
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
                  controller: _weishauptOutdoorRegController,
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
                  controller: _weishauptFlowRegController,
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
                  controller: _weishauptReturnRegController,
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
                  controller: _weishauptHwRegController,
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
                  controller: _weishauptRoomRegController,
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
                  controller: _weishauptShiftRegController,
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
                  initialValue: _weishauptMultiplier,
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
                    if (val != null) setState(() => _weishauptMultiplier = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<bool>(
                  initialValue: _weishauptIsHolding,
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
                    if (val != null) setState(() => _weishauptIsHolding = val);
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
                  onPressed: _testingWeishaupt ? null : _testWeishauptConnection,
                  icon: _testingWeishaupt
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
                      final host = _weishauptHostController.text.trim();
                      final port =
                          int.tryParse(_weishauptPortController.text.trim());
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

  Widget _buildNibeModbusConfigCard(ECLProvider provider) {
    const accent = Color(0xFF42A5F5);

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
              const Icon(Icons.air_rounded,
                  color: accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'NIBE Wärmepumpe Konfiguration',
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
            'Modbus-TCP-Anbindung für NIBE S-Serie (S1155/S1255/S2125) und F-Serie (Modbus 40).',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),

          // ── Preset Selector ──────────────────────────────────
          DropdownButtonFormField<String>(
            initialValue: _nibePresetId,
            decoration: _decoration(
              label: 'NIBE Modell / Preset',
              icon: Icons.bookmarks_outlined,
            ),
            dropdownColor: const Color(0xFF2A2A32),
            items: NibeModbusConfig.presets.map((preset) {
              return DropdownMenuItem(
                value: preset.id,
                child: Text(preset.name, style: const TextStyle(fontSize: 13.5)),
              );
            }).toList(),
            onChanged: (id) {
              if (id == null) return;
              final preset =
                  NibeModbusConfig.presets.firstWhere((p) => p.id == id);
              setState(() {
                _nibePresetId = id;
                _nibePortController.text = preset.defaultPort.toString();
                _nibeUnitIdController.text = preset.defaultUnitId.toString();
                _nibeOutdoorRegController.text = preset.outdoorRegister.toString();
                _nibeFlowRegController.text = preset.flowRegister.toString();
                _nibeReturnRegController.text = preset.returnRegister.toString();
                _nibeHwRegController.text = preset.hotWaterRegister.toString();
                _nibeRoomRegController.text =
                    preset.roomTargetRegister?.toString() ?? '';
                _nibeShiftRegController.text =
                    preset.heatingCurveShiftRegister?.toString() ?? '';
                _nibeMultiplier = preset.multiplier;
                _nibeIsHolding = preset.isHoldingRegister;
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
                  controller: _nibeHostController,
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
                  controller: _nibePortController,
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
                  controller: _nibeUnitIdController,
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
            'NIBE Modbus Register-Adressen',
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
                  controller: _nibeOutdoorRegController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'BT1 Außentemperatur',
                    icon: Icons.thermostat_outlined,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _nibeFlowRegController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'BT2 Vorlauftemperatur',
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
                  controller: _nibeReturnRegController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'BT3 Rücklauftemperatur',
                    icon: Icons.rotate_left_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _nibeHwRegController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'BT6 Warmwasserspeicher',
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
                  controller: _nibeRoomRegController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'BT50 Raum-Soll (opt.)',
                    icon: Icons.home_outlined,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _nibeShiftRegController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration(
                    label: 'Kurvenverschiebung (opt.)',
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
                  initialValue: _nibeMultiplier,
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
                    if (val != null) setState(() => _nibeMultiplier = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<bool>(
                  initialValue: _nibeIsHolding,
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
                    if (val != null) setState(() => _nibeIsHolding = val);
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
                  onPressed: _testingNibe ? null : _testNibeConnection,
                  icon: _testingNibe
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
                      final host = _nibeHostController.text.trim();
                      final port =
                          int.tryParse(_nibePortController.text.trim());
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

  Widget _buildBillingCredentialsFields(ECLProvider provider) {
    final desc = provider.currentBillingDescriptor;
    final isBrunataHamburg = provider.selectedBillingId == 'brunata_hamburg';

    String title;
    String userLabel;
    String subtitle;
    String defaultPortal;

    switch (provider.selectedBillingId) {
      case 'brunata_hamburg':
        title = 'Brunata Portal-Zugang';
        userLabel = 'Kundennummer / Benutzername';
        subtitle =
            'Verschlüsselt lokal gespeichert für den monatlichen Abrechnungsabruf (portal.brunata-hamburg.de).';
        defaultPortal = 'https://portal.brunata-hamburg.de';
        break;
      case 'brunata_muenchen':
        title = 'Brunata München Portal-Zugang';
        userLabel = 'E-Mail / Benutzername / Kundennummer';
        subtitle =
            'Verschlüsselt lokal gespeichert für das BRUNATA-METRONA München Portal.';
        defaultPortal = 'https://meine.brunata-metrona.de';
        break;
      case 'brunata_huerth':
        title = 'Brunata Hürth Portal-Zugang';
        userLabel = 'Kundennummer / Benutzername';
        subtitle =
            'Verschlüsselt lokal gespeichert für das BRUNATA-METRONA Hürth Portal (Köln/Rheinland).';
        defaultPortal = 'https://portal.brunata-huerth.de';
        break;
      case 'kalo':
        title = 'KALO Bewohnerportal-Zugang';
        userLabel = 'E-Mail / Bewohner-ID / Kundennummer';
        subtitle =
            'Verschlüsselt lokal gespeichert für das KALO (Kalorimeta) Bewohnerportal.';
        defaultPortal = 'https://bewohner.kalo.de';
        break;
      case 'techem_smart':
        title = 'Techem Portal- & Smart System Zugang';
        userLabel = 'Benutzername / E-Mail-Adresse';
        subtitle =
            'Verschlüsselt lokal gespeichert für das Techem Mieter- und Kundenportal.';
        defaultPortal = 'https://kundenportal.techem.de';
        break;
      case 'ista_ecotrend':
        title = 'ista EcoTrend Portal- & API-Zugang';
        userLabel = 'E-Mail / ista Connect Benutzername';
        subtitle =
            'Verschlüsselt lokal gespeichert für ista EcoTrend (Essen) Webportal & REST API.';
        defaultPortal = 'https://ecotrend.ista.de';
        break;
      case 'minol_zenner':
        title = 'Minol e-Service Portal-Zugang';
        userLabel = 'Nutzername / Liegenschafts-ID';
        subtitle =
            'Verschlüsselt lokal gespeichert für das Minol e-Service Portal.';
        defaultPortal = 'https://www.minol.de/e-service-portal.html';
        break;
      default:
        title = '${desc.name} Portal-Zugang';
        userLabel = 'Benutzername / Kundennummer';
        subtitle =
            'Verschlüsselt lokal gespeichert für die Abrechnungssynchronisation.';
        defaultPortal = '';
    }

    const accent = Color(0xFFFFA726);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isBrunataHamburg) ...[
          _buildSimulatedBillingNotice(desc),
          const SizedBox(height: 14),
        ],
        Container(
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
                      color: accent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFECECF0),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
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
                  label: userLabel,
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
                  label: 'Kennwort / Passwort',
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _portalUrlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: _decoration(
                  label: 'Portal-URL / Endpunkt (optional)',
                  icon: Icons.link_rounded,
                ).copyWith(
                  helperText: defaultPortal.isNotEmpty
                      ? 'Standard: $defaultPortal'
                      : null,
                  helperStyle: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _testingBilling ? null : _testBillingConnection,
                icon: _testingBilling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : const Icon(Icons.sync_rounded, size: 18),
                label: Text(
                  _testingBilling
                      ? 'Synchronisiere...'
                      : '${desc.name} Daten abrufen',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: const BorderSide(color: accent),
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ],
          ),
        ),
      ],
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

  Widget _buildDiagnosticLogsTile(ECLProvider provider) {
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF382A18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long_rounded,
                    color: Color(0xFFFFA726), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aktivitäts- & Diagnoseprotokoll',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFECECF0),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Überwacht Messwertabrufe, Schreibbefehle & Fehlercodes live.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9E9EA8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF3A3A44), height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFFA726),
              side: const BorderSide(color: Color(0xFFFFA726)),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Protokoll & Diagnose öffnen'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LogScreen()),
              );
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
