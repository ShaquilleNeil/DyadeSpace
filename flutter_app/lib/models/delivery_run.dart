import 'package:cloud_firestore/cloud_firestore.dart';
import 'run_stop.dart';

/// Drew's delivery run for one day: an ordered list of stops,
/// stored as a single document with the stops embedded as maps
/// (simple on purpose - a run is always read and written whole).
class DeliveryRun {
  final String id;
  final DateTime date;
  final String driverId;
  final String createdBy;
  final List<RunStop> stops;

  /// Odometer readings (km) the driver enters at run start and
  /// run end. Distance = end - start; null until entered. The
  /// start reading is prefilled from the driver's previous run's
  /// end reading when one exists.
  final int? odometerStart;
  final int? odometerEnd;

  const DeliveryRun({
    required this.id,
    required this.date,
    required this.driverId,
    this.createdBy = '',
    this.stops = const [],
    this.odometerStart,
    this.odometerEnd,
  });

  List<RunStop> get orderedStops {
    final copy = [...stops]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return copy;
  }

  /// Every stop completed successfully (no failures).
  bool get isComplete =>
      stops.isNotEmpty && stops.every((s) => s.status == StopStatus.completed);

  bool get hasFailures => stops.any((s) => s.status == StopStatus.failed);

  /// Every stop is closed (completed or failed) - the run is over,
  /// possibly with issues when [hasFailures] is true.
  bool get isFinished =>
      stops.isNotEmpty && stops.every((s) => s.status != StopStatus.pending);

  int get completedCount =>
      stops.where((s) => s.status == StopStatus.completed).length;

  int get failedCount =>
      stops.where((s) => s.status == StopStatus.failed).length;

  /// Kilometres driven on this run, from the odometer readings.
  /// Null until both readings are entered and the end reading
  /// is not before the start.
  int? get distanceKm {
    if (odometerStart == null || odometerEnd == null) return null;
    final d = odometerEnd! - odometerStart!;
    return d < 0 ? null : d;
  }

  DeliveryRun copyWith({
    List<RunStop>? stops,
    int? odometerStart,
    int? odometerEnd,
  }) {
    return DeliveryRun(
      id: id,
      date: date,
      driverId: driverId,
      createdBy: createdBy,
      stops: stops ?? this.stops,
      odometerStart: odometerStart ?? this.odometerStart,
      odometerEnd: odometerEnd ?? this.odometerEnd,
    );
  }

  factory DeliveryRun.fromFirestore(DocumentSnapshot doc) {
    return DeliveryRun.fromMap(doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  factory DeliveryRun.fromMap(String id, Map<String, dynamic> map) {
    return DeliveryRun(
      id: id,
      date: map['date'] is Timestamp
          ? (map['date'] as Timestamp).toDate()
          : DateTime.now(),
      driverId: map['driverId'] as String? ?? '',
      createdBy: map['createdBy'] as String? ?? '',
      stops: (map['stops'] is List ? map['stops'] as List : const [])
          // Tolerant parse: one malformed stop (a non-map
          // element) must never fail the whole run list — the
          // bad element is dropped and the rest load.
          .whereType<Map>()
          .map((s) => RunStop.fromMap(Map<String, dynamic>.from(s)))
          .toList(),
      odometerStart: (map['odometerStart'] as num?)?.toInt(),
      odometerEnd: (map['odometerEnd'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': Timestamp.fromDate(date),
      'driverId': driverId,
      'createdBy': createdBy,
      'stops': stops.map((s) => s.toMap()).toList(),
      'odometerStart': odometerStart,
      'odometerEnd': odometerEnd,
    };
  }
}
