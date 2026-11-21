import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dyadespace/models/breadcrumb.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the Breadcrumb model (Part 3): map round-trip.
void main() {
  test('toMap/fromMap round-trip keeps lat, lng and time', () {
    final now = DateTime(2026, 11, 15, 8, 30);
    final real = Breadcrumb(id: 'c1', lat: 45.0001, lng: -73.00, at: now);
    final map = real.toMap();
    expect(map['lat'], 45.0001);
    expect(map['lng'], -73.00);
    expect(map['at'], isA<Timestamp>());
    final back = Breadcrumb.fromMap('c1', {
      'lat': 45.0001,
      'lng': -73.00,
      'at': Timestamp.fromDate(now),
    });
    expect(back.id, 'c1');
    expect(back.lat, 45.0001);
    expect(back.lng, -73.00);
    expect(back.at, now);
  });

  test('fromMap throws on missing fields instead of inventing 0,0/now', () {
    expect(() => Breadcrumb.fromMap('c2', {}), throwsFormatException);
    expect(() => Breadcrumb.fromMap('c3', {'lat': 45.5, 'lng': -73.6}),
        throwsFormatException);
    expect(
        () => Breadcrumb.fromMap('c4', {
              'lat': 45.5,
              'at': Timestamp.fromDate(DateTime(2026, 11, 15)),
            }),
        throwsFormatException);
  });

  test('tryFromMap returns null for malformed docs (skip-with-warning)', () {
    expect(Breadcrumb.tryFromMap('c2', {}), isNull);
    expect(
        Breadcrumb.tryFromMap('c5', {
          'lat': 45.5,
          'lng': -73.6,
          'at': Timestamp.fromDate(DateTime(2026, 11, 15)),
        }),
        isNotNull);
  });
}
