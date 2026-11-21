import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/site.dart';
import 'auth_provider.dart';

/// All job sites. Read directly here - sites are simple reference
/// data and do not need their own service class. Gated on sign-in
/// so signing out does not surface permission-denied errors.
final sitesProvider = StreamProvider<List<Site>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return FirebaseFirestore.instance
      .collection('sites')
      .orderBy('name')
      .snapshots()
      .map((snap) => snap.docs.map(Site.fromFirestore).toList());
});

/// siteId -> Site lookup, handy for cards and group headers.
final siteByIdProvider = Provider<Map<String, Site>>((ref) {
  final sites = ref.watch(sitesProvider).valueOrNull ?? [];
  return {for (final s in sites) s.id: s};
});
