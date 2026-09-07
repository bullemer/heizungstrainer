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
import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/ecl_reading.dart';
import 'package:heizungstrainer/models/generic_modbus_config.dart';
import 'package:heizungstrainer/models/bosch_buderus_ems_config.dart';
import 'package:heizungstrainer/models/telemetry_sample.dart';
import 'package:heizungstrainer/services/brunata_local_scraper_service.dart';
import 'package:heizungstrainer/services/database_service.dart';
import 'package:heizungstrainer/services/device_registry.dart';
import 'package:heizungstrainer/services/discovery_service.dart';
import 'package:heizungstrainer/services/energy_price_service.dart';
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
  final EnergyPriceService _energyPriceService;
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

  GenericModbusConfig _genericModbusConfig = const GenericModbusConfig();
  BoschBuderusEmsConfig _boschBuderusConfig = const BoschBuderusEmsConfig();

  String get selectedControllerId => _selectedControllerId;
  String get selectedBillingId => _selectedBillingId;
  HeatingController get activeController => _activeController;
  BillingProvider get activeBillingProvider => _activeBillingProvider;
  EnergyPriceService get energyPriceService => _energyPriceService;
  GenericModbusConfig get genericModbusConfig => _genericModbusConfig;
  BoschBuderusEmsConfig get boschBuderusConfig => _boschBuderusConfig;
  ControllerDescriptor get currentControllerDescriptor =>
      DeviceRegistry.getControllerDescriptor(_selectedControllerId);
  BillingProviderDescriptor get currentBillingDescriptor =>
      DeviceRegistry.getBillingProviderDescriptor(_selectedBillingId);
  bool get isSimulatedController =>
      _selectedControllerId != 'danfoss_ecl_310' &&
      _selectedControllerId != 'generic_modbus' &&
      _selectedControllerId != 'bosch_buderus_ems';
  bool get isGenericModbusController =>
      _selectedControllerId == 'generic_modbus';
  bool get isBoschBuderusEmsController =>
      _selectedControllerId == 'bosch_buderus_ems';
  bool get isSimulatedBilling => _selectedBillingId != 'brunata_hamburg';

  BrunataSyncState get brunataSyncState => _brunataSyncState;
  BrunataMeterData? get brunataData => _brunataData;
  String? get brunataSyncError => _brunataSyncError;
  bool get isBrunataSyncing => _brunataSyncState != BrunataSyncState.idle &&
      _brunataSyncState != BrunataSyncState.complete &&
      _brunataSyncState != BrunataSyncState.error;

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
    EnergyPriceService? energyPriceService,
    FlutterSecureStorage? secureStorage,
    bool autoLoadDatabase = true,
  })  : _modbusService = modbusService ?? ModbusService(),
        _discoveryService = discoveryService ?? DiscoveryService(),
        _brunataScraper = brunataScraper ?? BrunataLocalScraperService(),
        _databaseService = databaseService ?? DatabaseService.instance,
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _energyPriceService = energyPriceService ??
            EnergyPriceService(
              secureStorage: secureStorage ?? const FlutterSecureStorage(),
            ) {
    _activeController = DeviceRegistry.createController(
      _selectedControllerId,
      modbusService: _modbusService,
    );
    _activeBillingProvider = DeviceRegistry.createBillingProvider(
      _selectedBillingId,
      scraperService: _brunataScraper,
    );
    _brunataScraper.onStateChange = (state) {
      _brunataSyncState = state;
      notifyListeners();
    };
    if (autoLoadDatabase) {
      _initFromDatabase();
    }
    _initHardwareSettings();
  }

  Future<void> _initHardwareSettings() async {
    try {
      _genericModbusConfig = await GenericModbusConfig.load(_secureStorage);
      _boschBuderusConfig = await BoschBuderusEmsConfig.load(_secureStorage);
      final savedCtrl = await _secureStorage.read(key: _controllerStorageKey);
      if (savedCtrl != null && savedCtrl.isNotEmpty && savedCtrl != _selectedControllerId) {
        _selectedControllerId = savedCtrl;
      }
      _activeController = DeviceRegistry.createController(
        _selectedControllerId,
        modbusService: _modbusService,
        genericModbusConfig: _genericModbusConfig,
        boschBuderusConfig: _boschBuderusConfig,
      );
      final savedBill = await _secureStorage.read(key: _billingStorageKey);
      if (savedBill != null && savedBill.isNotEmpty && savedBill != _selectedBillingId) {
        _selectedBillingId = savedBill;
        _activeBillingProvider = DeviceRegistry.createBillingProvider(
          savedBill,
          scraperService: _brunataScraper,
        );
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
    );
    try {
      await _secureStorage.write(key: _controllerStorageKey, value: id);
    } catch (e) {
      debugPrint('[Provider] Could not persist selected controller: $e');
    }
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
    );
    try {
      await _secureStorage.write(key: _billingStorageKey, value: id);
    } catch (e) {
      debugPrint('[Provider] Could not persist selected billing provider: $e');
    }
    notifyListeners();
  }

  /// Starts simulation mode for previewing non-Danfoss controllers.
  Future<void> startSimulation() async {
    _connectionState = ECLConnectionState.connecting;
    _controllerIp = 'Simulation (${currentControllerDescriptor.brand})';
    _errorMessage = null;
    notifyListeners();

    try {
      await _activeController.connect(host: '127.0.0.1');
      _connectionState = ECLConnectionState.connected;
      _isReconnecting = false;
      _consecutivePollErrors = 0;
      notifyListeners();

      await refreshReadings();
      _startPolling();
    } catch (e) {
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

    _connectionState = ECLConnectionState.discovering;
    _errorMessage = null;
    _discoveryProgress = 0.0;
    notifyListeners();

    try {
      final hasPermission = await _ensureLocationPermission();
      if (!hasPermission) {
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

      _connectionState = ECLConnectionState.connecting;
      _controllerIp = ip;
      notifyListeners();

      await _modbusService.connect(ip);
      _connectionState = ECLConnectionState.connected;
      _consecutivePollErrors = 0;
      _isReconnecting = false;
      notifyListeners();

      await refreshReadings();
      _startPolling();
    } on ControllerNotFoundException catch (e) {
      _setError(e.message);
    } on ModbusCommunicationException catch (e) {
      _setError(e.message);
    } catch (e) {
      debugPrint('[Provider] Unexpected error: $e');
      _setError('Unerwarteter Fehler: $e');
    }
  }

  Future<void> connectToIp(String ip, {int? port}) async {
    _connectionState = ECLConnectionState.connecting;
    _errorMessage = null;
    _controllerIp = ip;
    _consecutivePollErrors = 0;
    _isReconnecting = false;
    notifyListeners();

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
      await refreshReadings();
      _startPolling();
    } on ModbusCommunicationException catch (e) {
      _setError(e.message);
    } catch (e) {
      debugPrint('[Provider] Connection error: $e');
      _setError('Verbindungsfehler: $e');
    }
  }

  void disconnect() {
    _stopPolling();
    if (_selectedControllerId == 'danfoss_ecl_310') {
      _modbusService.disconnect();
    } else {
      _activeController.disconnect();
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
      throw const ModbusCommunicationException(
        message: 'Keine Verbindung zum Regler.',
      );
    }

    if (_selectedControllerId != 'danfoss_ecl_310') {
      if (parameter.id == ECLRegisters.heatingCurveShift.id) {
        await _activeController.setHeatingCurveShift(value);
      } else if (parameter.id == ECLRegisters.roomTargetTemp.id) {
        await _activeController.setRoomTarget(value);
      }
      final reading = ECLReading(
        parameter: parameter,
        rawValue: parameter.displayToRaw(value),
        timestamp: DateTime.now(),
      );
      _readings[parameter.id] = reading;
      await _databaseService.cacheControllerReadings(_readings);
      notifyListeners();
      return reading;
    }

    final reading = await _modbusService.writeAndVerify(parameter, value);
    _readings[parameter.id] = reading;
    _databaseService.cacheControllerReadings(_readings);
    notifyListeners();
    return reading;
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

    try {
      final result = await _activeBillingProvider.syncData();

      if (result.success && result.data != null) {
        _brunataData = result.data;
        _brunataSyncState = BrunataSyncState.complete;
        _brunataSyncError = null;
        await _databaseService.cacheBrunataData(result.data!);
      } else {
        _brunataSyncError = result.errorMessage ??
            'Abrechnungs-Synchronisation fehlgeschlagen';
        _brunataSyncState = BrunataSyncState.error;
        _brunataData ??= BrunataMeterData.demo();
      }
    } catch (e) {
      _brunataSyncError = e.toString();
      _brunataSyncState = BrunataSyncState.error;
      _brunataData ??= BrunataMeterData.demo();
    }
    notifyListeners();
  }

  /// Triggers sync with the active billing provider (Brunata or simulation).
  Future<void> syncBrunataData() => syncBillingData();

  /// Whether credentials for the active billing provider are stored.
  Future<bool> hasBrunataCredentials() => _activeBillingProvider.hasCredentials();

  /// Currently stored username (or null).
  Future<String?> getBrunataUsername() => _brunataScraper.getUsername();

  /// Currently stored password (or null).
  Future<String?> getBrunataPassword() => _brunataScraper.getPassword();

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
    bool isCustom = true,
    bool syncAfterSave = false,
  }) async {
    await _activeBillingProvider.saveCredentials(
      username: username,
      password: password,
    );
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
