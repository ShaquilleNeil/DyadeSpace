import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/unit.dart';
import '../services/unit_service.dart';
import 'auth_provider.dart';

final unitServiceProvider = Provider<UnitService>((ref) => UnitService());

/// All units. Gated on sign-in so signing out does not surface
/// permission-denied errors — same pattern as
/// [allStagesProvider].
final allUnitsProvider = StreamProvider<List<Unit>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.watch(unitServiceProvider).watchAllUnits();
});

/// One site's units. Family provider.
final unitsForSiteProvider =
    StreamProvider.family<List<Unit>, String>((ref, siteId) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.watch(unitServiceProvider).watchUnitsForSite(siteId);
});
