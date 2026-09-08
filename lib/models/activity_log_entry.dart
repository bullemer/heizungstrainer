import 'dart:convert';

/// Severity level of an activity log entry.
enum ActivityLogLevel {
  info,
  success,
  warning,
  error;

  static ActivityLogLevel fromString(String value) {
    switch (value.toLowerCase()) {
      case 'success':
        return ActivityLogLevel.success;
      case 'warning':
      case 'warn':
        return ActivityLogLevel.warning;
      case 'error':
        return ActivityLogLevel.error;
      case 'info':
      default:
        return ActivityLogLevel.info;
    }
  }

  String toDbString() => name;
}

/// Functional category of the activity.
enum ActivityLogCategory {
  controllerRead,
  controllerWrite,
  connection,
  billing,
  securityGate,
  system;

  static ActivityLogCategory fromString(String value) {
    switch (value) {
      case 'controllerRead':
        return ActivityLogCategory.controllerRead;
      case 'controllerWrite':
        return ActivityLogCategory.controllerWrite;
      case 'connection':
        return ActivityLogCategory.connection;
      case 'billing':
        return ActivityLogCategory.billing;
      case 'securityGate':
        return ActivityLogCategory.securityGate;
      case 'system':
      default:
        return ActivityLogCategory.system;
    }
  }

  String toDbString() => name;

  String get displayName {
    switch (this) {
      case ActivityLogCategory.controllerRead:
        return 'Messwertabruf';
      case ActivityLogCategory.controllerWrite:
        return 'Schreibbefehl';
      case ActivityLogCategory.connection:
        return 'Verbindung';
      case ActivityLogCategory.billing:
        return 'Abrechnung';
      case ActivityLogCategory.securityGate:
        return 'Sicherheitssperre';
      case ActivityLogCategory.system:
        return 'System';
    }
  }
}

/// Represents a single activity, hardware communication event, or error code record.
class ActivityLogEntry {
  final int? id;
  final DateTime timestamp;
  final ActivityLogLevel level;
  final ActivityLogCategory category;
  final String? controllerId;
  final String action;
  final String message;
  final Map<String, dynamic>? details;
  final String? errorCode;
  final bool userAcknowledged;

  const ActivityLogEntry({
    this.id,
    required this.timestamp,
    required this.level,
    required this.category,
    this.controllerId,
    required this.action,
    required this.message,
    this.details,
    this.errorCode,
    this.userAcknowledged = false,
  });

  /// Factory constructor to create an entry with the current timestamp.
  factory ActivityLogEntry.create({
    required ActivityLogLevel level,
    required ActivityLogCategory category,
    String? controllerId,
    required String action,
    required String message,
    Map<String, dynamic>? details,
    String? errorCode,
    bool userAcknowledged = false,
  }) {
    return ActivityLogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      controllerId: controllerId,
      action: action,
      message: message,
      details: details,
      errorCode: errorCode,
      userAcknowledged: userAcknowledged,
    );
  }

  /// Converts the entry into a map for SQLite storage.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'level': level.toDbString(),
      'category': category.toDbString(),
      'controller_id': controllerId,
      'action': action,
      'message': message,
      'details': details != null
          ? jsonEncode(
              details,
              toEncodable: (nonEncodable) => nonEncodable.toString(),
            )
          : null,
      'error_code': errorCode,
      'user_acknowledged': userAcknowledged ? 1 : 0,
    };
  }

  /// Deserializes a database row into an [ActivityLogEntry].
  factory ActivityLogEntry.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? parsedDetails;
    final rawDetails = map['details'] as String?;
    if (rawDetails != null && rawDetails.isNotEmpty) {
      try {
        parsedDetails = jsonDecode(rawDetails) as Map<String, dynamic>;
      } catch (_) {
        parsedDetails = {'raw': rawDetails};
      }
    }

    return ActivityLogEntry(
      id: map['id'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      level: ActivityLogLevel.fromString(map['level'] as String),
      category: ActivityLogCategory.fromString(map['category'] as String),
      controllerId: map['controller_id'] as String?,
      action: map['action'] as String,
      message: map['message'] as String,
      details: parsedDetails,
      errorCode: map['error_code'] as String?,
      userAcknowledged: (map['user_acknowledged'] as int? ?? 0) == 1,
    );
  }

  /// Converts the entry into a sanitized JSON object for backoffice transmission.
  Map<String, dynamic> toJson({bool anonymize = true}) {
    final cleanDetails = Map<String, dynamic>.from(details ?? {});
    if (anonymize) {
      // Remove any sensitive keys if present in details
      cleanDetails.remove('password');
      cleanDetails.remove('token');
      cleanDetails.remove('privateKey');
      cleanDetails.remove('km200Key');
      cleanDetails.remove('gatewayPassword');
      cleanDetails.remove('credentials');
    }

    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'category': category.name,
      'controllerId': controllerId,
      'action': action,
      'message': message,
      'details': cleanDetails,
      'errorCode': errorCode,
      'userAcknowledged': userAcknowledged,
    };
  }

  ActivityLogEntry copyWith({
    int? id,
    DateTime? timestamp,
    ActivityLogLevel? level,
    ActivityLogCategory? category,
    String? controllerId,
    String? action,
    String? message,
    Map<String, dynamic>? details,
    String? errorCode,
    bool? userAcknowledged,
  }) {
    return ActivityLogEntry(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      level: level ?? this.level,
      category: category ?? this.category,
      controllerId: controllerId ?? this.controllerId,
      action: action ?? this.action,
      message: message ?? this.message,
      details: details ?? this.details,
      errorCode: errorCode ?? this.errorCode,
      userAcknowledged: userAcknowledged ?? this.userAcknowledged,
    );
  }

  @override
  String toString() {
    return 'ActivityLogEntry(id: $id, time: $timestamp, level: ${level.name}, cat: ${category.name}, ctrl: $controllerId, code: $errorCode, msg: $message)';
  }
}
