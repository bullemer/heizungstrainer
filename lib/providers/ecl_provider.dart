/// Central state management for the ECL 310 controller connection and readings.
///
/// Includes reading history tracking for sparkline trend charts.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/ecl_reading.dart';
import 'package:heizungstrainer/services/brunata_local_scraper_service.dart';
import 'package:heizungstrainer/services/discovery_service.dart';
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

  ECLConnectionState _connectionState = ECLConnectionState.disconnected;
  String? _controllerIp;
  String? _errorMessage;
  Map<String, ECLReading> _readings = {};
  Timer? _pollingTimer;
  double _discoveryProgress = 0.0;

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

  // ──────────────────────────────────────────────────────────────────
  // Constructor
  // ──────────────────────────────────────────────────────────────────

  ECLProvider({
    ModbusService? modbusService,
    DiscoveryService? discoveryService,
    BrunataLocalScraperService? brunataScraper,
  })  : _modbusService = modbusService ?? ModbusService(),
        _discoveryService = discoveryService ?? DiscoveryService(),
        _brunataScraper = brunataScraper ?? BrunataLocalScraperService() {
    _brunataScraper.onStateChange = (state) {
      _brunataSyncState = state;
      notifyListeners();
    };
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

  Future<void> connectToIp(String ip) async {
    _connectionState = ECLConnectionState.connecting;
    _errorMessage = null;
    _controllerIp = ip;
    notifyListeners();

    try {
      await _modbusService.connect(ip);
      await _discoveryService.saveControllerIp(ip);
      _connectionState = ECLConnectionState.connected;
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
    _modbusService.disconnect();
    _connectionState = ECLConnectionState.disconnected;
    _controllerIp = null;
    _errorMessage = null;
    _readings = {};
    _history.clear();
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────
  // Reading + History
  // ──────────────────────────────────────────────────────────────────

  Future<void> refreshReadings() async {
    if (!isConnected) return;

    try {
      _readings = await _modbusService.readAllParameters();

      // Record history for each reading
      for (final entry in _readings.entries) {
        final queue = _history.putIfAbsent(
          entry.key,
          () => Queue<double>(),
        );
        queue.addLast(entry.value.displayValue);
        while (queue.length > _maxHistoryLength) {
          queue.removeFirst();
        }
      }

      notifyListeners();
    } on ModbusCommunicationException catch (e) {
      _stopPolling();
      _setError(e.message);
    }
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

    final reading = await _modbusService.writeAndVerify(parameter, value);
    _readings[parameter.id] = reading;
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
  // Brunata Portal Sync
  // ──────────────────────────────────────────────────────────────────

  /// Triggers a headless browser sync with the Brunata billing portal.
  Future<void> syncBrunataData() async {
    if (isBrunataSyncing) return;

    _brunataSyncError = null;
    _brunataSyncState = BrunataSyncState.initializing;
    notifyListeners();

    final result = await _brunataScraper.syncFromPortal();

    if (result.success && result.data != null) {
      _brunataData = result.data;
      _brunataSyncState = BrunataSyncState.complete;
      _brunataSyncError = null;
    } else {
      _brunataSyncError = result.errorMessage;
      _brunataSyncState = BrunataSyncState.error;
      // Fall back to demo data if no prior data exists
      _brunataData ??= BrunataMeterData.demo();
    }
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────
  // Brunata Settings (credentials + tariff)
  // ──────────────────────────────────────────────────────────────────

  /// Whether Brunata login credentials are stored.
  Future<bool> hasBrunataCredentials() => _brunataScraper.hasCredentials();

  /// Currently stored Brunata username (or null).
  Future<String?> getBrunataUsername() => _brunataScraper.getUsername();

  /// Currently stored Brunata password (or null).
  Future<String?> getBrunataPassword() => _brunataScraper.getPassword();

  /// Configured price per kWh used to estimate heating cost.
  Future<double> getPricePerKwh() => _brunataScraper.getPricePerKwh();

  /// Persists the Brunata credentials and tariff, then optionally re-syncs.
  Future<void> saveBrunataSettings({
    required String username,
    required String password,
    required double pricePerKwh,
    bool syncAfterSave = false,
  }) async {
    await _brunataScraper.saveCredentials(
      username: username,
      password: password,
    );
    await _brunataScraper.savePricePerKwh(pricePerKwh);
    // Recompute the cost of already-loaded data against the new tariff so the
    // UI reflects the change without requiring a full re-sync.
    final existing = _brunataData;
    if (existing != null) {
      _brunataData = existing.copyWithPrice(pricePerKwh);
    }
    notifyListeners();
    if (syncAfterSave) {
      await syncBrunataData();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    _modbusService.disconnect();
    super.dispose();
  }
}
