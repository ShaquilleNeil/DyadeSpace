import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/material_request.dart';
import '../services/material_request_service.dart';
import 'auth_provider.dart';

final materialRequestServiceProvider =
    Provider<MaterialRequestService>((ref) => MaterialRequestService());

/// Every material request, newest first. Gated on sign-in: when
/// signed out it yields an empty list instead of running a
/// Firestore query that would fail with permission-denied
/// during sign-out.
final materialRequestsProvider = StreamProvider<List<MaterialRequest>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.watch(materialRequestServiceProvider).watchAllRequests();
});

/// Requests still waiting on a manager: asked for, or approved
/// but not on a run yet. Drives the badge on the Board's
/// Requests shortcut.
final openMaterialRequestsCountProvider = Provider<int>((ref) {
  final list = ref.watch(materialRequestsProvider).valueOrNull ?? [];
  return list.where((r) => r.isOpen).length;
});

/// Approved requests not on a run yet: the run builder offers
/// them as one-tap pickups.
final approvedMaterialRequestsProvider =
    StreamProvider<List<MaterialRequest>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.watch(materialRequestServiceProvider).watchApprovedRequests();
});
