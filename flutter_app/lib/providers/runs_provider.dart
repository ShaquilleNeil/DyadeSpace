import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/delivery_run.dart';
import 'auth_provider.dart';

/// Every run, all drivers (the driver screen's provider is the
/// same shape but filtered to the signed-in driver). Gated on
/// sign-in like the other providers, for the sign-out reason.
/// Lives here (not in runs_progress_screen.dart) so the web
/// control center can use it without importing a phone screen.
///
/// Capped at the 200 most recent runs: the collection grows by
/// a run per driver per day, and no screen needs anything older
/// (the board and the requests queue only look at today; the
/// progress screen is a recent-history view). Loading every run
/// ever made the stream — and every snapshot — grow without
/// bound.
final allRunsProvider = StreamProvider<List<DeliveryRun>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return FirebaseFirestore.instance
      .collection('runs')
      .orderBy('date', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) {
    final runs = snap.docs.map(DeliveryRun.fromFirestore).toList();
    runs.sort((a, b) => a.date.compareTo(b.date));
    return runs;
  });
});

/// Same calendar day - the comparison every run screen uses.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
