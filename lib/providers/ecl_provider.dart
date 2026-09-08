/// Central state management for the ECL 310 controller connection and readings.
///
/// Includes reading history tracking for sparkline trend charts.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/controllers/generic_modbus_controller.dart';
import 'package:heizungstrainer/controllers/bosch_buderus_ems_controller.dart';
import 'package:heizungstrainer/controllers/viessmann_controller.dart';
import 'package:heizungstrainer/controllers/vaillant_ebusd_controller.dart';
import 'package:heizungstrainer/controllers/weishaupt_wem_controller.dart';
import 'package:heizungstrainer/controllers/nibe_modbus_controller.dart';
import 'package:heizungstrainer/controllers/mock_heating_controller.dart';
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/ecl_reading.dart';
import 'package:heizungstrainer/models/generic_modbus_config.dart';
import 'package:heizungstrainer/models/bosch_buderus_ems_config.dart';
import 'package:heizungstrainer/models/viessmann_config.dart';
import 'package:heizungstrainer/models/vaillant_ebusd_config.dart';
import 'package:heizungstrainer/models/activity_log_entry.dart';
import 'package:heizungstrainer/models/weishaupt_wem_config.dart';
import 'package:heizungstrainer/models/nibe_modbus_config.dart';
import 'package:heizungstrainer/models/telemetry_sample.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/brunata_local_scraper_service.dart';
import 'package:heizungstrainer/services/database_service.dart';
import 'package:heizungstrainer/services/device_registry.dart';
import 'package:heizungstrainer/services/discovery_service.dart';
import 'package:heizungstrainer/services/energy_price_service.dart';
import 'package:heizungstrainer/exceptions/license_exception.dart';
import 'package:heizungstrainer/models/license_info.dart';
import 'package:heizungstrainer/services/license_service.dart';
import 'package:heizungstrainer/services/modbus_service.dart';

/// Connection lifecycle states for the ECL 310 controller.
enum ECLConnectionState {
  disconnected,
  discovering,
  connecting,
  connected,
  error,
}

/// Provides reactive state for the ECL 310 controller connection,
/// sensor readings, trend history, and safe setpoint mutations.
class ECLProvider extends ChangeNotifier {
  final ModbusService _modbusService;
  final DiscoveryService _discoveryService;
  final BrunataLocalScraperService _brunataScraper;
  final DatabaseService _databaseService;
  final ActivityLogService _logService;
  final EnergyPriceService _energyPriceService;
  final LicenseService _licenseService;
  final FlutterSecureStorage _secureStorage;

  static const String _controllerStorageKey = 'selected_controller_id';
  static const String _billingStorageKey = 'selected_billing_id';

  String _selectedControllerId = 'danfoss_ecl_310';
  String _selectedBillingId = 'brunata_hamburg';
  late HeatingController _activeController;
  late BillingProvider _activeBillingProvider;

  ECLConnectionState _connectionState = ECLConnectionState.disconnected;
  String? _controllerIp;
  String? _errorMessage;
  Map<String, ECLReading> _readings = {};
  Timer? _pollingTimer;
  double _discoveryProgress = 0.0;
  bool _isReconnecting = false;
  bool _isOfflineMode = false;
  int _consecutivePollErrors = 0;
  static const int _maxConsecutivePollErrors = 3;
  DateTime? _lastSuccessfulPoll;
  DateTime? _lastTelemetryRecorded;

  /// Brunata portal sync state.
  BrunataSyncState _brunataSyncState = BrunataSyncState.idle;
  BrunataMeterData? _brunataData;
  String? _brunataSyncError;
  DateTime? _lastBillingSyncTime;

  /// Maximum number of historical readings to keep per parameter.
  static const int _maxHistoryLength = 60; // ~10 minutes at 10s polling

  /// Polling interval for automatic sensor value refresh.
  static const Duration _pollingInterval = Duration(seconds: 10);

  /// Historical readings per parameter, keyed by parameter ID.
  /// Each queue holds up to [_maxHistoryLength] display values.
  final Map<String, Queue<double>> _history = {};

  // ──────────────────────────────────────────────────────────────────
  // Public Getters
  // ──────────────────────────────────────────────────────────────────

  ECLConnectionState get connectionState => _connectionState;
  String? get controllerIp => _controllerIp;
  String? get errorMessage => _errorMessage;
  Map<String, ECLReading> get readings => Map.unmodifiable(_readings);
  double get discoveryProgress => _discoveryProgress;
  bool get isConnected => _connectionState == ECLConnectionState.connected;
  bool get isReconnecting => _isReconnecting;
  bool get isOfflineMode => _isOfflineMode;
  bool get hasCachedReadings => _readings.isNotEmpty;
  DateTime? get lastSuccessfulPoll => _lastSuccessfulPoll;
  DatabaseService get databaseService => _databaseService;
  ActivityLogService get logService => _logService;

  GenericModbusConfig _genericModbusConfig = const GenericModbusConfig();
  BoschBuderusEmsConfig _boschBuderusConfig = const BoschBuderusEmsConfig();
  ViessmannConfig _viessmannConfig = const ViessmannConfig();
  VaillantEbusdConfig _vaillantConfig = const VaillantEbusdConfig();
  WeishauptWemConfig _weishauptConfig = const WeishauptWemConfig();
  NibeModbusConfig _nibeConfig = const NibeModbusConfig();

  String get selectedControllerId => _selectedControllerId;
  String get selectedBillingId => _selectedBillingId;
  HeatingController get activeController => _activeController;
  BillingProvider get activeBillingProvider => _activeBillingProvider;
  EnergyPriceService get energyPriceService => _energyPriceService;
  LicenseService get licenseService => _licenseService;
  GenericModbusConfig get genericModbusConfig => _genericModbusConfig;
  BoschBuderusEmsConfig get boschBuderusConfig => _boschBuderusConfig;
  ViessmannConfig get viessmannConfig => _viessmannConfig;
  VaillantEbusdConfig get vaillantConfig => _vaillantConfig;
  WeishauptWemConfig get weishauptConfig => _weishauptConfig;
  NibeModbusConfig get nibeConfig => _nibeConfig;
  ControllerDescriptor get currentControllerDescriptor =>
      DeviceRegistry.getControllerDescriptor(_selectedControllerId);
  BillingProviderDescriptor get currentBillingDescriptor =>
      DeviceRegistry.getBillingProviderDescriptor(_selectedBillingId);
  bool get isSimulatedController =>
      _selectedControllerId != 'danfoss_ecl_310' &&
      _selectedControllerId != 'generic_modbus' &&
      _selectedControllerId != 'bosch_buderus_ems' &&
      _selectedControllerId != 'viessmann_vicare' &&
      _selectedControllerId != 'vaillant_ebusd' &&
      _selectedControllerId != 'weishaupt_wem' &&
      _selectedControllerId != 'nibe_modbus';
  bool get isGenericModbusController =>
      _selectedControllerId == 'generic_modbus';
  bool get isBoschBuderusEmsController =>
      _selectedControllerId == 'bosch_buderus_ems';
  bool get isViessmannController =>
      _selectedControllerId == 'viessmann_vicare';
  bool get isVaillantController =>
      _selectedControllerId == 'vaillant_ebusd';
  bool get isWeishauptController =>
      _selectedControllerId == 'weishaupt_wem';
  bool get isNibeController =>
      _selectedControllerId == 'nibe_modbus';

  final Map<String, bool> _billingHasCredentials = {};

  bool get isSimulatedBilling {
    if (_selectedBillingId == 'brunata_hamburg') return false;
    return !(_billingHasCredentials[_selectedBillingId] ?? false);
  }

  BrunataSyncState get brunataSyncState => _brunataSyncState;
  BrunataMeterData? get brunataData => _brunataData;
  String? get brunataSyncError => _brunataSyncError;
  DateTime? get lastBillingSyncTime => _lastBillingSyncTime;
  bool get hasBillingSynced => _lastBillingSyncTime != null;
  bool get isBrunataSyncing => _brunataSyncState != BrunataSyncState.idle &&
      _brunataSyncState != BrunataSyncState.complete &&
      _brunataSyncState != BrunataSyncState.error;

  void setLastBillingSyncTime(DateTime? time) {
    _lastBillingSyncTime = time;
    notifyListeners();
  }

  @visibleForTesting
  void setConnectedForTesting({
    String? ip,
    String? errorMessage,
    ECLConnectionState state = ECLConnectionState.connected,
  }) {
    _controllerIp = ip;
    _errorMessage = errorMessage;
    _connectionState = state;
    notifyListeners();
  }

  @visibleForTesting
  void setBrunataDataForTesting(BrunataMeterData? data) {
    _brunataData = data;
    notifyListeners();
  }

  /// Returns the trend history for a parameter as a list of display values.
  List<double> getHistory(ECLParameter parameter) {
    return _history[parameter.id]?.toList() ?? [];
  }

  void openOfflineMode() {
    _isOfflineMode = true;
    notifyListeners();
  }

  void exitOfflineMode() {
    _isOfflineMode = false;
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────
  // Constructor
  // ──────────────────────────────────────────────────────────────────

  ECLProvider({
    ModbusService? modbusService,
    DiscoveryService? discoveryService,
    BrunataLocalScraperService? brunataScraper,
    DatabaseService? databaseService,
    ActivityLogService? logService,
    EnergyPriceService? energyPriceService,
    LicenseService? licenseService,
    FlutterSecureStorage? secureStorage,
    bool autoLoadDatabase = true,
  })  : _modbusService = modbusService ?? ModbusService(),
        _discoveryService = discoveryService ?? DiscoveryService(),
        _brunataScraper = brunataScraper ?? BrunataLocalScraperService(),
        _databaseService = databaseService ?? DatabaseService.instance,
        _logService = logService ??
            (autoLoadDatabase
                ? ActivityLogService.instance
                : ActivityLogService(enablePersistence: false)),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _energyPriceService = energyPriceService ??
            EnergyPriceService(
              secureStorage: secureStorage ?? const FlutterSecureStorage(),
            ),
        _licenseService = licenseService ??
            (autoLoadDatabase
                ? LicenseService(secureStorage: secureStorage ?? const FlutterSecureStorage())
                : LicenseService(initialTier: LicenseTier.pro)) {
    _activeController = DeviceRegistry.createController(
      _selectedControllerId,
      modbusService: _modbusService,
    );
    _activeBillingProvider = DeviceRegistry.createBillingProvider(
      _selectedBillingId,
      scraperService: _brunataScraper,
      secureStorage: _secureStorage,
    );
    _brunataScraper.onStateChange = (state) {
      _brunataSyncState = state;
      notifyListeners();
    };
    if (autoLoadDatabase) {
      _initFromDatabase();
      _logService.init();
      _licenseService.init();
    }
    _initHardwareSettings();
  }

  Future<void> _initHardwareSettings() async {
    try {
      _genericModbusConfig = await GenericModbusConfig.load(_secureStorage);
      _boschBuderusConfig = await BoschBuderusEmsConfig.load(_secureStorage);
      _viessmannConfig = await ViessmannConfig.load(_secureStorage);
      _vaillantConfig = await VaillantEbusdConfig.load(_secureStorage);
      _weishauptConfig = await WeishauptWemConfig.load(_secureStorage);
      _nibeConfig = await NibeModbusConfig.load(_secureStorage);
      final savedCtrl = await _secureStorage.read(key: _controllerStorageKey);
      if (savedCtrl != null && savedCtrl.isNotEmpty && savedCtrl != _selectedControllerId) {
        _selectedControllerId = savedCtrl;
      }
      if (_connectionState == ECLConnectionState.disconnected &&
          _activeController is! MockHeatingController) {
        _activeController = DeviceRegistry.createController(
          _selectedControllerId,
          modbusService: _modbusService,
          genericModbusConfig: _genericModbusConfig,
          boschBuderusConfig: _boschBuderusConfig,
          viessmannConfig: _viessmannConfig,
          vaillantConfig: _vaillantConfig,
          weishauptConfig: _weishauptConfig,
          nibeConfig: _nibeConfig,
        );
      }
      final savedBill = await _secureStorage.read(key: _billingStorageKey);
      if (savedBill != null && savedBill.isNotEmpty && savedBill != _selectedBillingId) {
        _selectedBillingId = savedBill;
        _activeBillingProvider = DeviceRegistry.createBillingProvider(
          savedBill,
          scraperService: _brunataScraper,
          secureStorage: _secureStorage,
        );
        _billingHasCredentials[savedBill] = await _activeBillingProvider.hasCredentials();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[Provider] Error loading hardware settings from storage: $e');
    }
  }

  /// Sets the active heating controller hardware or simulation.
  Future<void> setSelectedController(String id) async {
    if (_selectedControllerId == id) return;
    if (isConnected) {
      disconnect();
    }
    _selectedControllerId = id;
    _activeController = DeviceRegistry.createController(
      id,
      modbusService: _modbusService,
      genericModbusConfig: _genericModbusConfig,
      boschBuderusConfig: _boschBuderusConfig,
      viessmannConfig: _viessmannConfig,
      vaillantConfig: _vaillantConfig,
      weishauptConfig: _weishauptConfig,
      nibeConfig: _nibeConfig,
    );
    try {
      await _secureStorage.write(key: _controllerStorageKey, value: id);
    } catch (e) {
      debugPrint('[Provider] Could not persist selected controller: $e');
    }
    final desc = currentControllerDescriptor;
    await _logService.logConnection(
      controllerId: id,
      action: 'CONTROLLER_SELECTED',
      message: 'Reglermodell ausgewählt: ${desc.brand} (${desc.model})',
      details: {'controllerId': id, 'brand': desc.brand, 'model': desc.model, 'protocol': desc.protocol.name},
    );
    notifyListeners();
  }

  /// Updates and persists the Generic Modbus TCP configuration.
  Future<void> updateGenericModbusConfig(GenericModbusConfig config) async {
    _genericModbusConfig = config;
    await config.save(_secureStorage);
    if (_selectedControllerId == 'generic_modbus') {
      if (_activeController is GenericModbusController) {
        (_activeController as GenericModbusController).updateConfig(config);
      } else {
        _activeController = DeviceRegistry.createController(
          'generic_modbus',
          modbusService: _modbusService,
          genericModbusConfig: config,
          boschBuderusConfig: _boschBuderusConfig,
          viessmannConfig: _viessmannConfig,
          vaillantConfig: _vaillantConfig,
          weishauptConfig: _weishauptConfig,
          nibeConfig: _nibeConfig,
        );
      }
    }
    notifyListeners();
  }

  /// Updates and persists the Bosch / Buderus EMS-ESP configuration.
  Future<void> updateBoschBuderusConfig(BoschBuderusEmsConfig config) async {
    _boschBuderusConfig = config;
    await config.save(_secureStorage);
    if (_selectedControllerId == 'bosch_buderus_ems') {
      if (_activeController is BoschBuderusEmsController) {
        (_activeController as BoschBuderusEmsController).updateConfig(config);
      } else {
        _activeController = DeviceRegistry.createController(
          'bosch_buderus_ems',
          modbusService: _modbusService,
          genericModbusConfig: _genericModbusConfig,
          boschBuderusConfig: config,
          viessmannConfig: _viessmannConfig,
          vaillantConfig: _vaillantConfig,
          weishauptConfig: _weishauptConfig,
          nibeConfig: _nibeConfig,
        );
      }
    }
    notifyListeners();
  }

  /// Updates and persists the Viessmann configuration.
  Future<void> updateViessmannConfig(ViessmannConfig config) async {
    _viessmannConfig = config;
    await config.save(_secureStorage);
    if (_selectedControllerId == 'viessmann_vicare') {
      if (_activeController is ViessmannController) {
        (_activeController as ViessmannController).updateConfig(config);
      } else {
        _activeController = DeviceRegistry.createController(
          'viessmann_vicare',
          modbusService: _modbusService,
          genericModbusConfig: _genericModbusConfig,
          boschBuderusConfig: _boschBuderusConfig,
          viessmannConfig: config,
          vaillantConfig: _vaillantConfig,
          weishauptConfig: _weishauptConfig,
          nibeConfig: _nibeConfig,
        );
      }
    }
    notifyListeners();
  }

  /// Updates and persists the Vaillant eBUSd configuration.
  Future<void> updateVaillantConfig(VaillantEbusdConfig config) async {
    _vaillantConfig = config;
    await config.save(_secureStorage);
    if (_selectedControllerId == 'vaillant_ebusd') {
      if (_activeController is VaillantEbusdController) {
        (_activeController as VaillantEbusdController).updateConfig(config);
      } else {
        _activeController = DeviceRegistry.createController(
          'vaillant_ebusd',
          modbusService: _modbusService,
          genericModbusConfig: _genericModbusConfig,
          boschBuderusConfig: _boschBuderusConfig,
          viessmannConfig: _viessmannConfig,
          vaillantConfig: config,
          weishauptConfig: _weishauptConfig,
          nibeConfig: _nibeConfig,
        );
      }
    }
    notifyListeners();
  }

  /// Updates and persists the Weishaupt WEM configuration.
  Future<void> updateWeishauptConfig(WeishauptWemConfig config) async {
    _weishauptConfig = config;
    await config.save(_secureStorage);
    if (_selectedControllerId == 'weishaupt_wem') {
      if (_activeController is WeishauptWemController) {
        (_activeController as WeishauptWemController).updateConfig(config);
      } else {
        _activeController = DeviceRegistry.createController(
          'weishaupt_wem',
          modbusService: _modbusService,
          genericModbusConfig: _genericModbusConfig,
          boschBuderusConfig: _boschBuderusConfig,
          viessmannConfig: _viessmannConfig,
          vaillantConfig: _vaillantConfig,
          weishauptConfig: config,
          nibeConfig: _nibeConfig,
        );
      }
    }
    notifyListeners();
  }

  /// Updates and persists the NIBE Modbus configuration.
  Future<void> updateNibeConfig(NibeModbusConfig config) async {
    _nibeConfig = config;
    await config.save(_secureStorage);
    if (_selectedControllerId == 'nibe_modbus') {
      if (_activeController is NibeModbusController) {
        (_activeController as NibeModbusController).updateConfig(config);
      } else {
        _activeController = DeviceRegistry.createController(
          'nibe_modbus',
          modbusService: _modbusService,
          genericModbusConfig: _genericModbusConfig,
          boschBuderusConfig: _boschBuderusConfig,
          viessmannConfig: _viessmannConfig,
          vaillantConfig: _vaillantConfig,
          weishauptConfig: _weishauptConfig,
          nibeConfig: config,
        );
      }
    }
    notifyListeners();
  }

  /// Sets the active billing and sub-metering provider.
  Future<void> setSelectedBillingProvider(String id) async {
    if (_selectedBillingId == id) return;
    _selectedBillingId = id;
    _activeBillingProvider = DeviceRegistry.createBillingProvider(
      id,
      scraperService: _brunataScraper,
      secureStorage: _secureStorage,
    );
    try {
      final hasCreds = await _activeBillingProvider.hasCredentials();
      _billingHasCredentials[id] = hasCreds;
      await _secureStorage.write(key: _billingStorageKey, value: id);
    } catch (e) {
      debugPrint('[Provider] Could not persist selected billing provider: $e');
    }
    final billDesc = currentBillingDescriptor;
    await _logService.logBilling(
      billingId: id,
      action: 'BILLING_PROVIDER_SELECTED',
      message: 'Abrechnungsdienst gewählt: ${billDesc.name} (${billDesc.organization})',
      details: {'providerId': id, 'name': billDesc.name},
    );
    notifyListeners();
  }

  /// Starts simulation mode for previewing controllers.
  Future<void> startSimulation() async {
    _connectionState = ECLConnectionState.connecting;
    _controllerIp = 'Simulation (${currentControllerDescriptor.brand})';
    _errorMessage = null;
    notifyListeners();

    await _logService.logConnection(
      controllerId: _selectedControllerId,
      action: 'START_SIMULATION',
      message: 'Starte Simulationsmodus für ${currentControllerDescriptor.brand}...',
    );

    try {
      if (_activeController is! MockHeatingController) {
        final desc = currentControllerDescriptor;
        _activeController = MockHeatingController(
          id: desc.id,
          brandName: desc.brand,
          modelName: desc.model,
          protocol: desc.protocol,
        );
      }
      await _activeController.connect(host: '127.0.0.1');
      _connectionState = ECLConnectionState.connected;
      _isReconnecting = false;
      _consecutivePollErrors = 0;
      notifyListeners();

      _logService.logConnection(
        controllerId: _selectedControllerId,
        action: 'SIMULATION_CONNECTED',
        message: 'Simulationslauf aktiv für ${currentControllerDescriptor.brand} (${currentControllerDescriptor.model})',
        success: true,
      );

      await refreshReadings();
      _startPolling();
    } catch (e) {
      _logService.logConnection(
        controllerId: _selectedControllerId,
        action: 'SIMULATION_START_FAILED',
        message: 'Fehler beim Starten der Simulation: $e',
        success: false,
        errorCode: 'SIMULATION_START_ERROR',
        details: {'error': e.toString()},
      );
      _setError('Fehler beim Starten der Simulation: $e');
    }
  }

  Future<void> _initFromDatabase() async {
    try {
      final cachedReadings =
          await _databaseService.getCachedControllerReadings();
      if (cachedReadings.isNotEmpty && _readings.isEmpty) {
        _readings = cachedReadings;
        _lastSuccessfulPoll = cachedReadings.values.first.timestamp;
        for (final entry in cachedReadings.entries) {
          if (!entry.value.isSensorDisconnected) {
            _history
                .putIfAbsent(entry.key, () => Queue<double>())
                .add(entry.value.displayValue);
          }
        }
        notifyListeners();
      }

      final cachedBrunata = await _databaseService.getCachedBrunataData();
      if (cachedBrunata != null && _brunataData == null) {
        if (cachedBrunata.pricePerKwh == 0.10) {
          final effectivePrice = await _energyPriceService.getEffectivePrice(
            billingProviderId: _selectedBillingId,
          );
          _brunataData = cachedBrunata.copyWithPrice(effectivePrice);
          await _databaseService.cacheBrunataData(_brunataData!);
        } else {
          _brunataData = cachedBrunata;
        }
        notifyListeners();
      }

      final cachedSyncTime = await _databaseService.getLastBillingSyncTime();
      if (cachedSyncTime != null) {
        _lastBillingSyncTime = cachedSyncTime;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[Provider] Error loading cache from SQLite: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Permissions
  // ──────────────────────────────────────────────────────────────────

  Future<bool> _ensureLocationPermission() async {
    var status = await Permission.location.status;
    debugPrint('[Provider] Location permission status: $status');
    if (status.isGranted) return true;
    status = await Permission.location.request();
    debugPrint('[Provider] Location permission after request: $status');
    return status.isGranted;
  }

  // ──────────────────────────────────────────────────────────────────
  // Connection Management
  // ──────────────────────────────────────────────────────────────────

  Future<void> connectToController() async {
    if (isSimulatedController) {
      await startSimulation();
      return;
    }

    if (_selectedControllerId == 'generic_modbus') {
      await connectToIp(_genericModbusConfig.host, port: _genericModbusConfig.port);
      return;
    }

    if (_selectedControllerId == 'bosch_buderus_ems') {
      await connectToIp(_boschBuderusConfig.host, port: _boschBuderusConfig.port);
      return;
    }

    if (_selectedControllerId == 'viessmann_vicare') {
      await connectToIp(_viessmannConfig.host, port: _viessmannConfig.port);
      return;
    }

    if (_selectedControllerId == 'vaillant_ebusd') {
      await connectToIp(_vaillantConfig.host, port: _vaillantConfig.port);
      return;
    }

    if (_selectedControllerId == 'weishaupt_wem') {
      await connectToIp(_weishauptConfig.host, port: _weishauptConfig.port);
      return;
    }

    if (_selectedControllerId == 'nibe_modbus') {
      await connectToIp(_nibeConfig.host, port: _nibeConfig.port);
      return;
    }

    _connectionState = ECLConnectionState.discovering;
    _errorMessage = null;
    _discoveryProgress = 0.0;
    notifyListeners();

    _logService.logConnection(
      controllerId: _selectedControllerId,
      action: 'DISCOVERY_START',
      message: 'Starte automatische Reglersuche im lokalen Netzwerk...',
    );

    try {
      final hasPermission = await _ensureLocationPermission();
      if (!hasPermission) {
        _logService.logConnection(
          controllerId: _selectedControllerId,
          action: 'PERMISSION_DENIED',
          message: 'Standortberechtigung für Netzwerk-Scan verweigert.',
          success: false,
          errorCode: 'PERMISSION_DENIED',
        );
        _setError('Standortberechtigung wird benötigt, um die WiFi-IP-Adresse '
            'zu ermitteln. Bitte erteilen Sie die Berechtigung in den Einstellungen.');
        return;
      }

      final ip = await _discoveryService.discoverController(
        onProgress: (scanned, total) {
          _discoveryProgress = scanned / total;
          notifyListeners();
        },
      );

      _logService.logConnection(
        controllerId: _selectedControllerId,
        action: 'CONTROLLER_DISCOVERED',
        message: 'Regler unter IP $ip im Netzwerk gefunden.',
        details: {'ip': ip},
      );

      _connectionState = ECLConnectionState.connecting;
      _controllerIp = ip;
      notifyListeners();

      await _modbusService.connect(ip);
      _connectionState = ECLConnectionState.connected;
      _consecutivePollErrors = 0;
      _isReconnecting = false;
      notifyListeners();

      _logService.logConnection(
        controllerId: _selectedControllerId,
        action: 'CONNECTED',
        message: 'Erfolgreich über Modbus TCP mit Regler $ip verbunden.',
        success: true,
        details: {'ip': ip},
      );

      await refreshReadings();
      _startPolling();
    } on ControllerNotFoundException catch (e) {
      _logService.logConnection(
        controllerId: _selectedControllerId,
        action: 'CONTROLLER_NOT_FOUND',
        message: 'Kein LAN-Zugriff oder Regler im Subnetz nicht gefunden: ${e.message}',
        success: false,
        errorCode: 'LAN_UNREACHABLE',
        details: {'failureDomain': 'lan_access'},
      );
      _setError(e.message);
    } on ModbusCommunicationException catch (e) {
      _logService.logConnection(
        controllerId: _selectedControllerId,
        action: 'MODBUS_CONNECT_FAILED',
        message: e.message,
        success: false,
        errorCode: 'CONTROLLER_SYNC_ERROR',
        details: {'failureDomain': 'controller_sync'},
      );
      _setError(e.message);
    } catch (e) {
      debugPrint('[Provider] Unexpected error: $e');
      final errLower = e.toString().toLowerCase();
      final isLanIssue = errLower.contains('network is unreachable') ||
          errLower.contains('no route to host') ||
          errLower.contains('connection refused') ||
          errLower.contains('socketexception') ||
          errLower.contains('timed out') ||
          errLower.contains('os error: 101') ||
          errLower.contains('os error: 111') ||
          errLower.contains('os error: 113');
      final errorCode = isLanIssue ? 'LAN_UNREACHABLE' : 'UNEXPECTED_CONNECTION_ERROR';
      final failureMsg = isLanIssue
          ? 'Kein LAN-Zugriff: Regler im lokalen Netzwerk nicht erreichbar. Bitte Heim-WLAN und Subnetz prüfen.'
          : 'Unerwarteter Verbindungsfehler: $e';

      _logService.logConnection(
        controllerId: _selectedControllerId,
        action: isLanIssue ? 'LAN_UNREACHABLE' : 'CONNECT_ERROR',
        message: failureMsg,
        success: false,
        errorCode: errorCode,
        details: {'error': e.toString(), 'failureDomain': isLanIssue ? 'lan_access' : 'general'},
      );
      _setError(failureMsg);
    }
  }

  Future<void> connectToIp(String ip, {int? port}) async {
    _connectionState = ECLConnectionState.connecting;
    _errorMessage = null;
    _controllerIp = ip;
    _consecutivePollErrors = 0;
    _isReconnecting = false;
    notifyListeners();

    _logService.logConnection(
      controllerId: _selectedControllerId,
      action: 'CONNECT_IP_START',
      message: 'Verbinde manuell mit $ip${port != null ? ":$port" : ""}...',
      details: {'ip': ip, 'port': port},
    );

    try {
      if (_selectedControllerId == 'danfoss_ecl_310') {
        await _modbusService.connect(ip);
      } else {
        await _activeController.connect(host: ip, port: port);
      }
      await _discoveryService.saveControllerIp(ip);
      _connectionState = ECLConnectionState.connected;
      _consecutivePollErrors = 0;
      _isReconnecting = false;
      notifyListeners();

      _logService.logConnection(
        controllerId: _selectedControllerId,
        action: 'CONNECTED',
        message: 'Erfolgreich verbunden mit $ip${port != null ? ":$port" : ""}',
        success: true,
        details: {'ip': ip, 'port': port},
      );

      await refreshReadings();
      _startPolling();
    } on ModbusCommunicationException catch (e) {
      _logService.logConnection(
        controllerId: _selectedControllerId,
        action: 'CONNECT_FAILED',
        message: 'Verbindung fehlgeschlagen: ${e.message}',
        success: false,
        errorCode: 'CONTROLLER_SYNC_ERROR',
        details: {'ip': ip, 'port': port, 'failureDomain': 'controller_sync'},
      );
      _setError(e.message);
    } catch (e) {
      debugPrint('[Provider] Connection error: $e');
      final errLower = e.toString().toLowerCase();
      final isLanIssue = errLower.contains('network is unreachable') ||
          errLower.contains('no route to host') ||
          errLower.contains('connection refused') ||
          errLower.contains('socketexception') ||
          errLower.contains('timed out') ||
          errLower.contains('os error: 101') ||
          errLower.contains('os error: 111') ||
          errLower.contains('os error: 113');
      final errorCode = isLanIssue ? 'LAN_UNREACHABLE' : 'CONNECTION_ERROR';
      final failureMsg = isLanIssue
          ? 'Kein LAN-Zugriff: Regler unter $ip ist im lokalen Netzwerk nicht erreichbar. Bitte Heim-WLAN und Subnetz prüfen.'
          : 'Verbindungsfehler: $e';

      _logService.logConnection(
        controllerId: _selectedControllerId,
        action: isLanIssue ? 'LAN_UNREACHABLE' : 'CONNECT_FAILED',
        message: failureMsg,
        success: false,
        errorCode: errorCode,
        details: {
          'ip': ip,
          'port': port,
          'error': e.toString(),
          'failureDomain': isLanIssue ? 'lan_access' : 'general',
        },
      );
      _setError(failureMsg);
    }
  }

  void disconnect() {
    _stopPolling();
    if (_selectedControllerId == 'danfoss_ecl_310') {
      _modbusService.disconnect();
    } else {
      _activeController.disconnect();
    }
    _logService.logConnection(
      controllerId: _selectedControllerId,
      action: 'DISCONNECTED',
      message: 'Verbindung zu Regler ($_selectedControllerId) getrennt.',
      success: true,
    );
    if (_activeController is MockHeatingController) {
      _activeController = DeviceRegistry.createController(
        _selectedControllerId,
        modbusService: _modbusService,
        genericModbusConfig: _genericModbusConfig,
        boschBuderusConfig: _boschBuderusConfig,
        viessmannConfig: _viessmannConfig,
        vaillantConfig: _vaillantConfig,
        weishauptConfig: _weishauptConfig,
        nibeConfig: _nibeConfig,
      );
    }
    _connectionState = ECLConnectionState.disconnected;
    _controllerIp = null;
    _errorMessage = null;
    _consecutivePollErrors = 0;
    _isReconnecting = false;
    _lastSuccessfulPoll = null;
    _readings = {};
    _history.clear();
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────
  // Reading + History
  // ──────────────────────────────────────────────────────────────────

  Future<void> refreshReadings() async {
    if (!isConnected) return;

    if (_selectedControllerId != 'danfoss_ecl_310') {
      try {
        final telemetry = await _activeController.readTelemetry();
        _readings[ECLRegisters.outdoorTemp.id] = ECLReading(
          parameter: ECLRegisters.outdoorTemp,
          rawValue: ECLRegisters.outdoorTemp
              .displayToRaw(telemetry.outdoorTemp ?? 7.5),
          timestamp: telemetry.timestamp,
        );
        _readings[ECLRegisters.flowTemp.id] = ECLReading(
          parameter: ECLRegisters.flowTemp,
          rawValue: ECLRegisters.flowTemp
              .displayToRaw(telemetry.flowTemp ?? 46.0),
          timestamp: telemetry.timestamp,
        );
        _readings[ECLRegisters.returnTemp.id] = ECLReading(
          parameter: ECLRegisters.returnTemp,
          rawValue: ECLRegisters.returnTemp
              .displayToRaw(telemetry.returnTemp ?? 36.0),
          timestamp: telemetry.timestamp,
        );
        _readings[ECLRegisters.hotWaterTemp.id] = ECLReading(
          parameter: ECLRegisters.hotWaterTemp,
          rawValue: ECLRegisters.hotWaterTemp
              .displayToRaw(telemetry.hotWaterTemp ?? 52.0),
          timestamp: telemetry.timestamp,
        );
        _readings[ECLRegisters.heatingCurveShift.id] = ECLReading(
          parameter: ECLRegisters.heatingCurveShift,
          rawValue: ECLRegisters.heatingCurveShift
              .displayToRaw(telemetry.heatingCurveShift ?? 0.0),
          timestamp: telemetry.timestamp,
        );
        _readings[ECLRegisters.roomTargetTemp.id] = ECLReading(
          parameter: ECLRegisters.roomTargetTemp,
          rawValue: ECLRegisters.roomTargetTemp
              .displayToRaw(telemetry.roomTarget ?? 20.0),
          timestamp: telemetry.timestamp,
        );
        _consecutivePollErrors = 0;
        _isReconnecting = false;
        _lastSuccessfulPoll = telemetry.timestamp;

        // Monitor sensor disconnection error code 19200
        for (final entry in _readings.entries) {
          if (entry.value.isSensorDisconnected) {
            await _logService.logRead(
              controllerId: _selectedControllerId,
              action: 'SENSOR_FAULT_DETECTED',
              message: 'Sensorfehler 19200 (Unterbrechung/defekt): ${entry.key}',
              errorCode: 'SENSOR_FAULT_19200',
              level: ActivityLogLevel.warning,
              details: {'parameterId': entry.key, 'rawValue': entry.value.rawValue},
            );
          }
        }

        await _logService.logRead(
          controllerId: _selectedControllerId,
          action: 'READ_TELEMETRY_SUCCESS',
          message: 'Telemetrie aktualisiert: VL ${telemetry.flowTemp?.toStringAsFixed(1) ?? "-"}°C, RL ${telemetry.returnTemp?.toStringAsFixed(1) ?? "-"}°C, AT ${telemetry.outdoorTemp?.toStringAsFixed(1) ?? "-"}°C',
          details: {
            'flowTemp': telemetry.flowTemp,
            'returnTemp': telemetry.returnTemp,
            'outdoorTemp': telemetry.outdoorTemp,
            'hotWaterTemp': telemetry.hotWaterTemp,
            'heatingCurveShift': telemetry.heatingCurveShift,
            'roomTarget': telemetry.roomTarget,
          },
        );

        for (final entry in _readings.entries) {
          if (!entry.value.isSensorDisconnected) {
            final queue = _history.putIfAbsent(
              entry.key,
              () => Queue<double>(),
            );
            queue.addLast(entry.value.displayValue);
            while (queue.length > _maxHistoryLength) {
              queue.removeFirst();
            }
          }
        }

        await _persistReadings(_readings);
        notifyListeners();
      } catch (e) {
        debugPrint('[Provider] Controller reading error: $e');
        final errLower = e.toString().toLowerCase();
        final isTimeout = errLower.contains('timeout') || errLower.contains('timed out');
        final syncErrorCode = isTimeout ? 'CONTROLLER_SYNC_TIMEOUT' : 'CONTROLLER_SYNC_ERROR';

        await _logService.logError(
          action: 'READ_TELEMETRY_FAILED',
          message: 'Fehler beim Synchronisieren des Reglers: $e',
          controllerId: _selectedControllerId,
          category: ActivityLogCategory.controllerRead,
          errorCode: syncErrorCode,
          exception: e,
          details: {'failureDomain': 'controller_sync', 'error': e.toString()},
        );
        if (!isSimulatedController) {
          _consecutivePollErrors++;
          if (_consecutivePollErrors < _maxConsecutivePollErrors) {
            _isReconnecting = true;
            notifyListeners();
          } else {
            _stopPolling();
            _isReconnecting = false;
            _setError('Fehler beim Auslesen des Reglers: $e');
          }
        }
      }
      return;
    }

    try {
      final newReadings = await _modbusService.readAllParameters();
      _readings.addAll(newReadings);
      _consecutivePollErrors = 0;
      if (_isReconnecting) {
        _isReconnecting = false;
      }
      _lastSuccessfulPoll = DateTime.now();

      // Monitor sensor disconnection error code 19200
      for (final entry in newReadings.entries) {
        if (entry.value.isSensorDisconnected) {
          await _logService.logRead(
            controllerId: _selectedControllerId,
            action: 'SENSOR_FAULT_DETECTED',
            message: 'Sensorfehler 19200: Fühler ${entry.value.parameter.name} getrennt/defekt.',
            errorCode: 'SENSOR_FAULT_19200',
            level: ActivityLogLevel.warning,
            details: {'parameterId': entry.key, 'rawValue': entry.value.rawValue},
          );
        }
      }

      await _logService.logRead(
        controllerId: _selectedControllerId,
        action: 'READ_MODBUS_SUCCESS',
        message: '${newReadings.length} Register-Messwerte über Modbus TCP aktualisiert.',
        details: {
          'registerCount': newReadings.length,
        },
      );

      // Record history for each valid reading (ignore disconnected sensors)
      for (final entry in newReadings.entries) {
        if (!entry.value.isSensorDisconnected) {
          final queue = _history.putIfAbsent(
            entry.key,
            () => Queue<double>(),
          );
          queue.addLast(entry.value.displayValue);
          while (queue.length > _maxHistoryLength) {
            queue.removeFirst();
          }
        }
      }

      // Persist latest state & telemetry to SQLite
      _persistReadings(_readings);

      notifyListeners();
    } on ModbusCommunicationException catch (e) {
      _consecutivePollErrors++;
      debugPrint(
        '[Provider] Polling error ($_consecutivePollErrors/$_maxConsecutivePollErrors): $e',
      );

      await _logService.logError(
        action: 'MODBUS_POLL_ERROR',
        message: 'Modbus-Abfragefehler: ${e.message}',
        controllerId: _selectedControllerId,
        category: ActivityLogCategory.controllerRead,
        errorCode: 'CONTROLLER_SYNC_ERROR',
        exception: e,
        details: {'failureDomain': 'controller_sync', 'error': e.message},
      );

      if (_consecutivePollErrors < _maxConsecutivePollErrors) {
        // Transient communication error: keep connected and flag reconnecting state
        _isReconnecting = true;
        notifyListeners();
      } else {
        // Exceeded retry limit: stop polling and transition to error
        _stopPolling();
        _isReconnecting = false;
        _setError(e.message);
      }
    }
  }

  Future<void> _persistReadings(Map<String, ECLReading> currentReadings) async {
    try {
      await _databaseService.cacheControllerReadings(currentReadings);

      final now = DateTime.now();
      if (_lastTelemetryRecorded == null ||
          now.difference(_lastTelemetryRecorded!) >=
              const Duration(seconds: 30)) {
        _lastTelemetryRecorded = now;

        final outdoor = currentReadings[ECLRegisters.outdoorTemp.id];
        final flow = currentReadings[ECLRegisters.flowTemp.id];
        final ret = currentReadings[ECLRegisters.returnTemp.id];
        final hw = currentReadings[ECLRegisters.hotWaterTemp.id];
        final shift = currentReadings[ECLRegisters.heatingCurveShift.id];
        final room = currentReadings[ECLRegisters.roomTargetTemp.id];

        final sample = TelemetrySample(
          timestamp: now,
          outdoorTemp: (outdoor != null && !outdoor.isSensorDisconnected)
              ? outdoor.displayValue
              : null,
          flowTemp: (flow != null && !flow.isSensorDisconnected)
              ? flow.displayValue
              : null,
          returnTemp: (ret != null && !ret.isSensorDisconnected)
              ? ret.displayValue
              : null,
          hotWaterTemp: (hw != null && !hw.isSensorDisconnected)
              ? hw.displayValue
              : null,
          heatingCurveShift: shift?.displayValue,
          roomTarget: room?.displayValue,
        );

        await _databaseService.insertTelemetry(sample);
      }
    } catch (e) {
      debugPrint('[Provider] Error buffering telemetry to SQLite: $e');
    }
  }

  /// Retrieves historical telemetry from SQLite for the specified duration.
  Future<List<TelemetrySample>> getTelemetryHistory({
    Duration duration = const Duration(hours: 24),
  }) async {
    final now = DateTime.now();
    return await _databaseService.getTelemetryHistory(
      from: now.subtract(duration),
      to: now,
    );
  }

  ECLReading? getReading(ECLParameter parameter) => _readings[parameter.id];

  // ──────────────────────────────────────────────────────────────────
  // Writing (Fail-Safe)
  // ──────────────────────────────────────────────────────────────────

  Future<ECLReading> writeParameter(
    ECLParameter parameter,
    double value,
  ) async {
    if (!isConnected) {
      await _logService.logError(
        action: 'WRITE_REJECTED_NO_CONNECTION',
        message: 'Schreibbefehl abgelehnt: Keine Verbindung zum Regler.',
        controllerId: _selectedControllerId,
        category: ActivityLogCategory.controllerWrite,
        errorCode: 'NO_CONNECTION',
      );
      throw const ModbusCommunicationException(
        message: 'Keine Verbindung zum Regler.',
      );
    }

    // License Gate: Enforce Pro tier for writing parameters to the controller
    if (!_licenseService.canWriteParameters) {
      await _logService.logSecurityGate(
        controllerId: _selectedControllerId,
        message: 'Schreibbefehl blockiert: Heizungstrainer Pro erforderlich.',
        details: {
          'parameterId': parameter.id,
          'parameterName': parameter.name,
          'tier': _licenseService.currentTier.name,
        },
        errorCode: 'LICENSE_PRO_REQUIRED',
      );
      throw const LicenseRequiredException(
        message: 'Das Verändern von Regler-Parametern erfordert Heizungstrainer Pro.',
        featureName: 'Parametrierung schreiben',
      );
    }

    // Safety Gate: Enforce parameter physical boundaries before issuing any command
    final validationError = parameter.validateDisplayValue(value);
    if (validationError != null) {
      await _logService.logSecurityGate(
        controllerId: _selectedControllerId,
        message: 'Sicherheitsverriegelung ausgelöst: $validationError',
        details: {
          'parameterId': parameter.id,
          'parameterName': parameter.name,
          'targetValue': value,
          'minValue': parameter.minValue,
          'maxValue': parameter.maxValue,
          'isWritable': parameter.isWritable,
        },
        errorCode: 'WRITE_OUT_OF_BOUNDS',
      );
      throw ModbusCommunicationException(message: validationError);
    }
    final rawTarget = parameter.displayToRaw(value);

    try {
      if (_selectedControllerId != 'danfoss_ecl_310' ||
          _activeController is MockHeatingController ||
          _controllerIp?.contains('Simulation') == true) {
        if (parameter.id == ECLRegisters.heatingCurveShift.id) {
          await _activeController.setHeatingCurveShift(value);
        } else if (parameter.id == ECLRegisters.roomTargetTemp.id) {
          await _activeController.setRoomTarget(value);
        }
        final reading = ECLReading(
          parameter: parameter,
          rawValue: rawTarget,
          timestamp: DateTime.now(),
        );
        _readings[parameter.id] = reading;
        await _databaseService.cacheControllerReadings(_readings);

        await _logService.logWrite(
          controllerId: _selectedControllerId,
          action: 'WRITE_PARAMETER_SUCCESS',
          message: '${parameter.name} erfolgreich auf $value ${parameter.unit} gesetzt.',
          details: {
            'parameterId': parameter.id,
            'parameterName': parameter.name,
            'value': value,
            'unit': parameter.unit,
            'controller': _selectedControllerId,
          },
          success: true,
        );

        notifyListeners();
        return reading;
      }

      final reading = await _modbusService.writeAndVerify(parameter, value);
      _readings[parameter.id] = reading;
      await _databaseService.cacheControllerReadings(_readings);

      await _logService.logWrite(
        controllerId: _selectedControllerId,
        action: 'WRITE_PARAMETER_VERIFIED',
        message: '${parameter.name} erfolgreich über Modbus auf $value ${parameter.unit} geschrieben und verifiziert.',
        details: {
          'parameterId': parameter.id,
          'parameterName': parameter.name,
          'modbusAddress': parameter.modbusAddress,
          'value': value,
          'unit': parameter.unit,
          'rawWritten': reading.rawValue,
        },
        success: true,
      );

      notifyListeners();
      return reading;
    } catch (e) {
      await _logService.logWrite(
        controllerId: _selectedControllerId,
        action: 'WRITE_PARAMETER_FAILED',
        message: 'Fehler beim Schreiben von ${parameter.name} ($value ${parameter.unit}): $e',
        details: {
          'parameterId': parameter.id,
          'parameterName': parameter.name,
          'targetValue': value,
          'error': e.toString(),
        },
        success: false,
        errorCode: 'WRITE_FAILED',
      );
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Polling
  // ──────────────────────────────────────────────────────────────────

  void _startPolling() {
    _stopPolling();
    _pollingTimer = Timer.periodic(_pollingInterval, (_) => refreshReadings());
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // ──────────────────────────────────────────────────────────────────
  // Error Handling
  // ──────────────────────────────────────────────────────────────────

  void _setError(String message) {
    _connectionState = ECLConnectionState.error;
    _errorMessage = message;
    notifyListeners();
  }

  void clearError() {
    if (_connectionState == ECLConnectionState.error) {
      _connectionState = ECLConnectionState.disconnected;
      _errorMessage = null;
      notifyListeners();
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Billing Provider Sync & Settings
  // ──────────────────────────────────────────────────────────────────

  /// Universal synchronization method for any configured billing provider.
  Future<void> syncBillingData() async {
    if (isBrunataSyncing) return;

    _brunataSyncError = null;
    _brunataSyncState = BrunataSyncState.initializing;
    notifyListeners();

    _logService.logBilling(
      billingId: _selectedBillingId,
      action: 'SYNC_START',
      message: 'Abrechnungs-Synchronisation gestartet für ${_activeBillingProvider.displayName}...',
      details: {'providerId': _selectedBillingId},
    );

    try {
      final result = await _activeBillingProvider.syncData();

      if (result.success && result.data != null) {
        _brunataData = result.data;
        _brunataSyncState = BrunataSyncState.complete;
        _brunataSyncError = null;
        _lastBillingSyncTime = DateTime.now();
        await _databaseService.cacheBrunataData(result.data!);

        _logService.logBilling(
          billingId: _selectedBillingId,
          action: 'SYNC_SUCCESS',
          message: 'Abrechnungsdaten erfolgreich synchronisiert: ${result.data!.consumedKwh.toStringAsFixed(0)} kWh erfasst.',
          success: true,
          details: {
            'consumedKwh': result.data!.consumedKwh,
            'currentPeriodCost': result.data!.currentBillingPeriodCost,
            'chartsCount': result.data!.charts.length,
          },
        );
      } else {
        _brunataSyncError = result.errorMessage ??
            'Abrechnungs-Synchronisation fehlgeschlagen';
        _brunataSyncState = BrunataSyncState.error;

        final errLower = _brunataSyncError!.toLowerCase();
        final isAuth = errLower.contains('passwort') ||
            errLower.contains('anmeldung') ||
            errLower.contains('401') ||
            errLower.contains('unauthorized') ||
            errLower.contains('zugangsdaten') ||
            errLower.contains('authentifizierung');
        final billingCode = isAuth ? 'BILLING_AUTH_FAILED' : 'BILLING_SYNC_ERROR';

        _logService.logBilling(
          billingId: _selectedBillingId,
          action: 'SYNC_FAILED',
          message: _brunataSyncError!,
          success: false,
          errorCode: billingCode,
          details: {
            'error': _brunataSyncError,
            'failureDomain': 'billing_sync',
          },
        );
      }
    } catch (e) {
      _brunataSyncError = e.toString();
      _brunataSyncState = BrunataSyncState.error;

      _logService.logBilling(
        billingId: _selectedBillingId,
        action: 'SYNC_EXCEPTION',
        message: 'Abrechnungsfehler: $e',
        success: false,
        errorCode: 'BILLING_EXCEPTION',
        details: {
          'exception': e.toString(),
          'failureDomain': 'billing_sync',
        },
      );
    }
    notifyListeners();
  }

  /// Triggers sync with the active billing provider (Brunata or simulation).
  Future<void> syncBrunataData() => syncBillingData();

  /// Whether credentials for the active billing provider are stored.
  Future<bool> hasBrunataCredentials() => _activeBillingProvider.hasCredentials();

  /// Currently stored username for the active billing provider.
  Future<String?> getBillingUsername() async {
    if (_selectedBillingId == 'brunata_hamburg') {
      return _brunataScraper.getUsername();
    }
    return _activeBillingProvider.getUsername();
  }

  /// Currently stored password for the active billing provider.
  Future<String?> getBillingPassword() async {
    if (_selectedBillingId == 'brunata_hamburg') {
      return _brunataScraper.getPassword();
    }
    return _activeBillingProvider.getPassword();
  }

  /// Currently configured portal URL for the active billing provider.
  Future<String> getBillingPortalUrl() async {
    if (_selectedBillingId == 'brunata_hamburg') {
      return _brunataScraper.getPortalUrl();
    }
    return _activeBillingProvider.getPortalUrl();
  }

  /// Updates portal URL for the active billing provider.
  Future<void> setBillingPortalUrl(String url) async {
    if (_selectedBillingId == 'brunata_hamburg') {
      await _brunataScraper.savePortalUrl(url);
    }
    await _activeBillingProvider.setPortalUrl(url);
    notifyListeners();
  }

  /// Legacy aliases
  Future<String?> getBrunataUsername() => getBillingUsername();
  Future<String?> getBrunataPassword() => getBillingPassword();

  /// Configured price per kWh used to estimate heating cost.
  ///
  /// Uses [EnergyPriceService] which respects user custom overrides
  /// and realistic energy carrier market benchmarks.
  Future<double> getPricePerKwh() =>
      _energyPriceService.getEffectivePrice(billingProviderId: _selectedBillingId);

  /// Queries dynamic market price benchmark for a given carrier.
  Future<EnergyCarrier> fetchDynamicMarketPrice({String? carrierId}) {
    return _energyPriceService.fetchDynamicMarketPrice(
      carrierId: carrierId ??
          (_selectedBillingId == 'brunata_hamburg'
              ? 'district_heating_hamburg'
              : 'national_average'),
    );
  }

  /// Directly updates and saves the energy price with optional carrier metadata.
  Future<void> updateEnergyPrice(
    double price, {
    String? carrierId,
    bool isCustom = true,
  }) async {
    await _energyPriceService.saveUserPrice(
      price,
      carrierId: carrierId,
      isCustom: isCustom,
    );
    await _activeBillingProvider.setPricePerKwh(price);
    if (_selectedBillingId == 'brunata_hamburg') {
      await _brunataScraper.savePricePerKwh(price);
    }
    final existing = _brunataData;
    if (existing != null) {
      _brunataData = existing.copyWithPrice(price);
      await _databaseService.cacheBrunataData(_brunataData!);
    }
    notifyListeners();
  }

  /// Persists settings for the active billing provider.
  Future<void> saveBillingSettings({
    required String username,
    required String password,
    required double pricePerKwh,
    String? carrierId,
    String? portalUrl,
    bool isCustom = true,
    bool syncAfterSave = false,
  }) async {
    await _activeBillingProvider.saveCredentials(
      username: username,
      password: password,
    );
    if (portalUrl != null && portalUrl.trim().isNotEmpty) {
      await _activeBillingProvider.setPortalUrl(portalUrl.trim());
    }
    _billingHasCredentials[_selectedBillingId] =
        username.trim().isNotEmpty && password.isNotEmpty;

    await _activeBillingProvider.setPricePerKwh(pricePerKwh);
    await _energyPriceService.saveUserPrice(
      pricePerKwh,
      carrierId: carrierId,
      isCustom: isCustom,
    );

    if (_selectedBillingId == 'brunata_hamburg') {
      await _brunataScraper.saveCredentials(
        username: username,
        password: password,
      );
      if (portalUrl != null && portalUrl.trim().isNotEmpty) {
        await _brunataScraper.savePortalUrl(portalUrl.trim());
      }
      await _brunataScraper.savePricePerKwh(pricePerKwh);
    }

    final existing = _brunataData;
    if (existing != null) {
      _brunataData = existing.copyWithPrice(pricePerKwh);
      await _databaseService.cacheBrunataData(_brunataData!);
    }
    notifyListeners();
    if (syncAfterSave) {
      await syncBillingData();
    }
  }

  /// Legacy alias for saveBillingSettings.
  Future<void> saveBrunataSettings({
    required String username,
    required String password,
    required double pricePerKwh,
    String? carrierId,
    bool isCustom = true,
    bool syncAfterSave = false,
  }) =>
      saveBillingSettings(
        username: username,
        password: password,
        pricePerKwh: pricePerKwh,
        carrierId: carrierId,
        isCustom: isCustom,
        syncAfterSave: syncAfterSave,
      );

  @override
  void dispose() {
    _stopPolling();
    _modbusService.disconnect();
    super.dispose();
  }
}
