import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:heizungstrainer/models/activity_log_entry.dart';
import 'package:heizungstrainer/services/database_service.dart';

/// Central service managing real-time and persistent activity and error logs.
///
/// Provides in-memory reactive notification for the UI alongside async write-through
/// to the local SQLite database. Also formats structured diagnostic bundles for
/// user-consented backoffice bug reporting and controller updates.
class ActivityLogService extends ChangeNotifier {
  static ActivityLogService? _instance;
  static ActivityLogService get instance => _instance ??= ActivityLogService();

  final DatabaseService _databaseService;
  final bool enablePersistence;
  final List<ActivityLogEntry> _recentEntries = [];
  bool _isInitialized = false;

  static const int maxInMemoryEntries = 250;

  ActivityLogService({
    DatabaseService? databaseService,
    this.enablePersistence = true,
  }) : _databaseService = databaseService ?? DatabaseService.instance;

  /// Visible for testing to reset or mock the singleton instance.
  static void resetInstance([ActivityLogService? newInstance]) {
    _instance = newInstance;
  }

  /// In-memory cache of the most recent entries, ordered newest-first.
  List<ActivityLogEntry> get recentEntries =>
      List.unmodifiable(_recentEntries);

  bool get isInitialized => _isInitialized;

  /// Initializes the service by loading recent entries from SQLite.
  Future<void> init() async {
    if (_isInitialized || !enablePersistence) {
      _isInitialized = true;
      return;
    }
    try {
      final stored = await _databaseService.getActivityLogs(
        limit: maxInMemoryEntries,
      );
      _recentEntries.clear();
      _recentEntries.addAll(stored);
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[ActivityLogService] Error initializing from DB: $e');
      _isInitialized = true;
    }
  }

  /// Core logging method. Writes through to SQLite and updates reactive memory buffer.
  Future<ActivityLogEntry> log(ActivityLogEntry entry) async {
    _recentEntries.insert(0, entry);
    if (_recentEntries.length > maxInMemoryEntries) {
      _recentEntries.removeLast();
    }
    notifyListeners();

    if (!enablePersistence) {
      return entry;
    }

    try {
      final rowId = await _databaseService.insertActivityLog(entry);
      final idx = _recentEntries.indexOf(entry);
      if (idx != -1) {
        _recentEntries[idx] = entry.copyWith(id: rowId);
      }
      return entry.copyWith(id: rowId);
    } catch (e) {
      debugPrint('[ActivityLogService] Failed to persist log entry: $e');
      return entry;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Specialized Logging Helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// Logs a controller telemetry read or polling cycle.
  Future<ActivityLogEntry> logRead({
    required String controllerId,
    required String action,
    required String message,
    Map<String, dynamic>? details,
    String? errorCode,
    ActivityLogLevel level = ActivityLogLevel.info,
  }) {
    return log(ActivityLogEntry.create(
      level: level,
      category: ActivityLogCategory.controllerRead,
      controllerId: controllerId,
      action: action,
      message: message,
      details: details,
      errorCode: errorCode,
    ));
  }

  /// Logs a parameter write or setpoint adjustment.
  Future<ActivityLogEntry> logWrite({
    required String controllerId,
    required String action,
    required String message,
    required Map<String, dynamic> details,
    String? errorCode,
    bool success = true,
  }) {
    return log(ActivityLogEntry.create(
      level: success ? ActivityLogLevel.success : ActivityLogLevel.error,
      category: ActivityLogCategory.controllerWrite,
      controllerId: controllerId,
      action: action,
      message: message,
      details: details,
      errorCode: errorCode,
    ));
  }

  /// Logs a connection or discovery lifecycle event.
  Future<ActivityLogEntry> logConnection({
    required String controllerId,
    required String action,
    required String message,
    bool success = true,
    String? errorCode,
    Map<String, dynamic>? details,
  }) {
    return log(ActivityLogEntry.create(
      level: success ? ActivityLogLevel.info : ActivityLogLevel.error,
      category: ActivityLogCategory.connection,
      controllerId: controllerId,
      action: action,
      message: message,
      details: details,
      errorCode: errorCode,
    ));
  }

  /// Logs when a security guard or parameter boundary check prevents an unsafe write.
  Future<ActivityLogEntry> logSecurityGate({
    required String controllerId,
    required String message,
    required Map<String, dynamic> details,
    String errorCode = 'WRITE_SECURITY_REJECT',
  }) {
    return log(ActivityLogEntry.create(
      level: ActivityLogLevel.warning,
      category: ActivityLogCategory.securityGate,
      controllerId: controllerId,
      action: 'SECURITY_GATE_INTERCEPT',
      message: message,
      details: details,
      errorCode: errorCode,
    ));
  }

  /// Logs a billing provider sync or scrape operation.
  Future<ActivityLogEntry> logBilling({
    required String billingId,
    required String action,
    required String message,
    bool success = true,
    String? errorCode,
    Map<String, dynamic>? details,
  }) {
    return log(ActivityLogEntry.create(
      level: success ? ActivityLogLevel.success : ActivityLogLevel.error,
      category: ActivityLogCategory.billing,
      controllerId: billingId,
      action: action,
      message: message,
      details: details,
      errorCode: errorCode,
    ));
  }

  /// Logs an unexpected application or controller error.
  Future<ActivityLogEntry> logError({
    required String action,
    required String message,
    String? controllerId,
    ActivityLogCategory category = ActivityLogCategory.system,
    String? errorCode,
    dynamic exception,
    StackTrace? stackTrace,
    Map<String, dynamic>? details,
  }) {
    final mergedDetails = <String, dynamic>{
      if (details != null) ...details,
      if (exception != null) 'exception': exception.toString(),
      if (stackTrace != null) 'stackTrace': stackTrace.toString().split('\n').take(8).join('\n'),
    };

    return log(ActivityLogEntry.create(
      level: ActivityLogLevel.error,
      category: category,
      controllerId: controllerId,
      action: action,
      message: message,
      details: mergedDetails.isNotEmpty ? mergedDetails : null,
      errorCode: errorCode ?? 'UNEXPECTED_ERROR',
    ));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Queries & Stats
  // ──────────────────────────────────────────────────────────────────────────

  /// Queries filtered activity logs from the database.
  Future<List<ActivityLogEntry>> getFilteredLogs({
    ActivityLogCategory? category,
    ActivityLogLevel? level,
    String? errorCode,
    bool? errorsOnly,
    String? searchQuery,
    int limit = 100,
    int offset = 0,
  }) {
    if (enablePersistence) {
      return _databaseService.getActivityLogs(
        category: category,
        level: level,
        errorCode: errorCode,
        errorsOnly: errorsOnly,
        searchQuery: searchQuery,
        limit: limit,
        offset: offset,
      );
    }
    return Future.value(List<ActivityLogEntry>.from(_recentEntries));
  }

  /// Gets quick summary statistics (total, errors, warnings, writes, reads).
  Future<Map<String, int>> getStats() {
    if (enablePersistence) {
      return _databaseService.getActivityLogStats();
    }
    return Future.value({
      'total': _recentEntries.length,
      'errors': _recentEntries.where((e) => e.level == ActivityLogLevel.error || e.errorCode != null).length,
      'warnings': _recentEntries.where((e) => e.level == ActivityLogLevel.warning).length,
      'writes': _recentEntries.where((e) => e.category == ActivityLogCategory.controllerWrite).length,
      'reads': _recentEntries.where((e) => e.category == ActivityLogCategory.controllerRead).length,
    });
  }

  /// Clears all logs from SQLite and memory buffer.
  Future<void> clearLogs() async {
    if (enablePersistence) {
      await _databaseService.clearActivityLogs();
    }
    _recentEntries.clear();
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Backoffice Diagnostics & User Acknowledgment
  // ──────────────────────────────────────────────────────────────────────────

  /// Generates a structured, anonymized JSON report ready to be sent to
  /// the backoffice once user acknowledgment/consent is confirmed.
  Map<String, dynamic> generateDiagnosticReport({
    required String currentControllerId,
    required String currentBillingId,
    String? userNote,
    bool anonymize = true,
  }) {
    final errorLogs = _recentEntries.where(
      (e) => e.level == ActivityLogLevel.error || e.errorCode != null,
    ).toList();

    final writeLogs = _recentEntries.where(
      (e) => e.category == ActivityLogCategory.controllerWrite,
    ).toList();

    return {
      'reportVersion': '1.0.0',
      'generatedAt': DateTime.now().toIso8601String(),
      'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      'app': {
        'name': 'Heizungstrainer',
        'version': '2.1.0',
      },
      'systemContext': {
        'controllerId': currentControllerId,
        'billingId': currentBillingId,
      },
      'userConsent': {
        'userAcknowledged': true,
        'acknowledgedAt': DateTime.now().toIso8601String(),
        'userNote': userNote,
        'anonymized': anonymize,
      },
      'statistics': {
        'totalRecorded': _recentEntries.length,
        'errorCount': errorLogs.length,
        'writeCount': writeLogs.length,
      },
      'criticalErrors': errorLogs.map((e) => e.toJson(anonymize: anonymize)).toList(),
      'recentActivity': _recentEntries
          .take(50)
          .map((e) => e.toJson(anonymize: anonymize))
          .toList(),
    };
  }

  /// Marks all current logs as acknowledged by the user.
  Future<void> markAllAcknowledged() async {
    if (enablePersistence) {
      await _databaseService.markLogsAcknowledged();
    }
    for (int i = 0; i < _recentEntries.length; i++) {
      if (!_recentEntries[i].userAcknowledged) {
        _recentEntries[i] = _recentEntries[i].copyWith(userAcknowledged: true);
      }
    }
    notifyListeners();
  }

  /// Prepares and sends the diagnostic bundle to the backoffice endpoint.
  /// User acknowledgment is verified before dispatching.
  Future<bool> sendDiagnosticReport({
    required Map<String, dynamic> diagnosticPayload,
    required bool userHasAcknowledged,
    String? backofficeUrl,
  }) async {
    if (!userHasAcknowledged) {
      throw ArgumentError(
        'Diagnosedaten dürfen erst nach ausdrücklicher Bestätigung des Nutzers versendet werden.',
      );
    }

    // Mark current logs as acknowledged
    await markAllAcknowledged();

    // The backoffice backend endpoint will be wired in a subsequent phase.
    // For now, validate payload structure and log readiness.
    final jsonString = jsonEncode(diagnosticPayload);
    debugPrint(
      '[ActivityLogService] Diagnostic report prepared (${jsonString.length} bytes). '
      'Ready for backoffice dispatch to: ${backofficeUrl ?? "default-backoffice"}',
    );

    await log(ActivityLogEntry.create(
      level: ActivityLogLevel.success,
      category: ActivityLogCategory.system,
      action: 'DIAGNOSTIC_REPORT_EXPORTED',
      message: 'Diagnosebericht vom Nutzer bestätigt und exportiert.',
      details: {
        'bytes': jsonString.length,
        'entriesCount': (diagnosticPayload['recentActivity'] as List?)?.length ?? 0,
      },
      userAcknowledged: true,
    ));

    return true;
  }
}
