/// Represents a single periodic telemetry measurement from the heating controller.
class TelemetrySample {
  final int? id;
  final DateTime timestamp;
  final double? outdoorTemp;
  final double? flowTemp;
  final double? returnTemp;
  final double? hotWaterTemp;
  final double? heatingCurveShift;
  final double? roomTarget;

  const TelemetrySample({
    this.id,
    required this.timestamp,
    this.outdoorTemp,
    this.flowTemp,
    this.returnTemp,
    this.hotWaterTemp,
    this.heatingCurveShift,
    this.roomTarget,
  });

  /// The temperature differential (Spreizung = Vorlauf - Rücklauf).
  double? get spread => (flowTemp != null && returnTemp != null)
      ? (flowTemp! - returnTemp!)
      : null;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'outdoor_temp': outdoorTemp,
        'flow_temp': flowTemp,
        'return_temp': returnTemp,
        'hot_water_temp': hotWaterTemp,
        'heating_curve_shift': heatingCurveShift,
        'room_target': roomTarget,
      };

  factory TelemetrySample.fromMap(Map<String, dynamic> map) {
    return TelemetrySample(
      id: map['id'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      outdoorTemp: (map['outdoor_temp'] as num?)?.toDouble(),
      flowTemp: (map['flow_temp'] as num?)?.toDouble(),
      returnTemp: (map['return_temp'] as num?)?.toDouble(),
      hotWaterTemp: (map['hot_water_temp'] as num?)?.toDouble(),
      heatingCurveShift: (map['heating_curve_shift'] as num?)?.toDouble(),
      roomTarget: (map['room_target'] as num?)?.toDouble(),
    );
  }
}
