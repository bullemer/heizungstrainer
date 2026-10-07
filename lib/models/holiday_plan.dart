import 'dart:convert';

/// Represents a scheduled or active holiday/absence mode plan.
class HolidayPlan {
  final String id;
  final String title;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final double setbackShift; // e.g. -3.0
  final double targetRoomTemp; // e.g. 16.0 °C
  final double normalShift; // previous normal shift to restore
  final double normalRoomTemp; // previous normal room temp to restore
  final double preheatHours; // hours before endDateTime to reheat, e.g. 4.0
  final double frostProtectionMinTemp; // minimum safety floor, e.g. 14.0 °C
  final bool isActive;
  final bool isCompleted;
  /// Whether the setback has actually been written to the controller. An active
  /// plan with a future start stays "armed" (false) until the app applies it.
  final bool setbackApplied;
  /// How the setback is applied: 'shift' (heating-curve shift) or 'room'
  /// (comfort room setpoint, e.g. Danfoss ECL applications without a shift).
  final String controlMode;
  /// Room-setpoint mode: lower the comfort setpoint by this many °C.
  final double roomSetbackKelvin;
  /// controlMode 'controller': the controller's holiday schedule (P1–P12)
  /// that holds this absence; the controller runs it without the app.
  final int? controllerSlot;
  final double estimatedSavingsKwh;
  final double estimatedSavingsEuro;
  final DateTime createdAt;

  const HolidayPlan({
    required this.id,
    required this.title,
    required this.startDateTime,
    required this.endDateTime,
    this.setbackShift = -3.0,
    this.targetRoomTemp = 16.0,
    this.normalShift = 0.0,
    this.normalRoomTemp = 21.0,
    this.preheatHours = 4.0,
    this.frostProtectionMinTemp = 14.0,
    this.isActive = true,
    this.isCompleted = false,
    this.setbackApplied = false,
    this.controlMode = 'shift',
    this.roomSetbackKelvin = 4.0,
    this.controllerSlot,
    this.estimatedSavingsKwh = 0.0,
    this.estimatedSavingsEuro = 0.0,
    required this.createdAt,
  });

  /// Total duration of the absence.
  Duration get duration => endDateTime.difference(startDateTime);

  /// Point in time when pre-heating must start before arrival.
  DateTime get preheatStartTime =>
      endDateTime.subtract(Duration(minutes: (preheatHours * 60).round()));

  /// Whether preheating phase is currently active.
  bool isPreheatingActive(DateTime now) {
    if (!isActive || isCompleted) return false;
    return now.isAfter(preheatStartTime) && now.isBefore(endDateTime);
  }

  /// Whether absence period is currently in progress.
  bool isInAbsencePeriod(DateTime now) {
    if (!isActive || isCompleted) return false;
    return now.isAfter(startDateTime) && now.isBefore(endDateTime);
  }

  /// Returns a copy of this plan with modified fields.
  bool get runsInController => controlMode == 'controller';

  HolidayPlan copyWith({
    String? id,
    String? title,
    DateTime? startDateTime,
    DateTime? endDateTime,
    double? setbackShift,
    double? targetRoomTemp,
    double? normalShift,
    double? normalRoomTemp,
    double? preheatHours,
    double? frostProtectionMinTemp,
    bool? isActive,
    bool? isCompleted,
    bool? setbackApplied,
    String? controlMode,
    double? roomSetbackKelvin,
    int? controllerSlot,
    double? estimatedSavingsKwh,
    double? estimatedSavingsEuro,
    DateTime? createdAt,
  }) {
    return HolidayPlan(
      id: id ?? this.id,
      title: title ?? this.title,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      setbackShift: setbackShift ?? this.setbackShift,
      targetRoomTemp: targetRoomTemp ?? this.targetRoomTemp,
      normalShift: normalShift ?? this.normalShift,
      normalRoomTemp: normalRoomTemp ?? this.normalRoomTemp,
      preheatHours: preheatHours ?? this.preheatHours,
      frostProtectionMinTemp:
          frostProtectionMinTemp ?? this.frostProtectionMinTemp,
      isActive: isActive ?? this.isActive,
      isCompleted: isCompleted ?? this.isCompleted,
      setbackApplied: setbackApplied ?? this.setbackApplied,
      controlMode: controlMode ?? this.controlMode,
      roomSetbackKelvin: roomSetbackKelvin ?? this.roomSetbackKelvin,
      controllerSlot: controllerSlot ?? this.controllerSlot,
      estimatedSavingsKwh: estimatedSavingsKwh ?? this.estimatedSavingsKwh,
      estimatedSavingsEuro: estimatedSavingsEuro ?? this.estimatedSavingsEuro,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'startDateTime': startDateTime.toIso8601String(),
      'endDateTime': endDateTime.toIso8601String(),
      'setbackShift': setbackShift,
      'targetRoomTemp': targetRoomTemp,
      'normalShift': normalShift,
      'normalRoomTemp': normalRoomTemp,
      'preheatHours': preheatHours,
      'frostProtectionMinTemp': frostProtectionMinTemp,
      'isActive': isActive,
      'isCompleted': isCompleted,
      'setbackApplied': setbackApplied,
      'controlMode': controlMode,
      'roomSetbackKelvin': roomSetbackKelvin,
      'controllerSlot': controllerSlot,
      'estimatedSavingsKwh': estimatedSavingsKwh,
      'estimatedSavingsEuro': estimatedSavingsEuro,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory HolidayPlan.fromJson(Map<String, dynamic> json) {
    return HolidayPlan(
      id: json['id'] as String,
      title: json['title'] as String,
      startDateTime: DateTime.parse(json['startDateTime'] as String),
      endDateTime: DateTime.parse(json['endDateTime'] as String),
      setbackShift: (json['setbackShift'] as num?)?.toDouble() ?? -3.0,
      targetRoomTemp: (json['targetRoomTemp'] as num?)?.toDouble() ?? 16.0,
      normalShift: (json['normalShift'] as num?)?.toDouble() ?? 0.0,
      normalRoomTemp: (json['normalRoomTemp'] as num?)?.toDouble() ?? 21.0,
      preheatHours: (json['preheatHours'] as num?)?.toDouble() ?? 4.0,
      frostProtectionMinTemp:
          (json['frostProtectionMinTemp'] as num?)?.toDouble() ?? 14.0,
      isActive: json['isActive'] as bool? ?? true,
      isCompleted: json['isCompleted'] as bool? ?? false,
      controlMode: json['controlMode'] as String? ?? 'shift',
      roomSetbackKelvin: (json['roomSetbackKelvin'] as num?)?.toDouble() ?? 4.0,
      controllerSlot: json['controllerSlot'] as int?,
      // Plans saved by <= 1.1.0 lowered the heating on activation.
      setbackApplied: json['setbackApplied'] as bool? ??
          ((json['isActive'] as bool? ?? true) && !(json['isCompleted'] as bool? ?? false)),
      estimatedSavingsKwh:
          (json['estimatedSavingsKwh'] as num?)?.toDouble() ?? 0.0,
      estimatedSavingsEuro:
          (json['estimatedSavingsEuro'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  static String encodeList(List<HolidayPlan> plans) {
    return jsonEncode(plans.map((p) => p.toJson()).toList());
  }

  static List<HolidayPlan> decodeList(String rawJson) {
    final list = jsonDecode(rawJson) as List<dynamic>;
    return list
        .map((item) => HolidayPlan.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
