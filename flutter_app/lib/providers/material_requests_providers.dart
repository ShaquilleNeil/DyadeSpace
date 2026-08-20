import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/material_request.dart';
import 'auth_providers.dart';
import 'firebase_providers.dart';

/// Role-aware material request feed: admin sees every request, a manager
/// sees requests for the project(s) they're on (including their own), a
/// worker sees only what they personally submitted.
final visibleMaterialRequestsProvider = StreamProvider<List<MaterialRequest>>((ref) {
  final me = ref.watch(currentEmployeeProvider).value;
  if (me == null) return Stream.value(const []);
  final firestore = ref.watch(firestoreServiceProvider);
  if (me.isAdmin) return firestore.watchAllMaterialRequests();
  if (me.isManager) return firestore.watchMaterialRequestsForProjects(me.projectIds);
  return firestore.watchMyMaterialRequests(me.id);
});

final materialRequestByIdProvider =
    StreamProvider.autoDispose.family<MaterialRequest?, String>((ref, requestId) {
  return ref.watch(firestoreServiceProvider).watchMaterialRequestById(requestId);
});

final materialRequestControllerProvider =
    Provider<MaterialRequestController>((ref) => MaterialRequestController(ref));

class MaterialRequestController {
  MaterialRequestController(this._ref);

  final Ref _ref;

  Future<void> submit(
    MaterialRequest request, {
    required List<File> photos,
  }) async {
    final firestore = _ref.read(firestoreServiceProvider);
    final requestId = await firestore.createMaterialRequest(request);
    if (photos.isNotEmpty) {
      final urls = await _ref
          .read(storageServiceProvider)
          .uploadMaterialRequestPhotos(requestId: requestId, files: photos);
      await firestore.setMaterialRequestPhotos(requestId, urls);
    }
  }

  Future<void> decide(
    String requestId, {
    required String status,
    required String decidedById,
    String? managerNote,
  }) {
    return _ref.read(firestoreServiceProvider).decideMaterialRequest(
          requestId,
          status: status,
          decidedById: decidedById,
          managerNote: managerNote,
        );
  }

  Future<void> delete(String requestId) {
    return _ref.read(firestoreServiceProvider).deleteMaterialRequest(requestId);
  }
}
