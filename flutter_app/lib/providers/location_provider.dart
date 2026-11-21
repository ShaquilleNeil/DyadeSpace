import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/location_service.dart';

/// The GPS service for clock-in. A provider (rather than a
/// direct `LocationService()` construction) so widget tests
/// can override it with a fixed fix — the clock-in button
/// otherwise takes a real fix and tests cannot steer where
/// the worker is.
final locationServiceProvider =
    Provider<LocationService>((ref) => LocationService());
