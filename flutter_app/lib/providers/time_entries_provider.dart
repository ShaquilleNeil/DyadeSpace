import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/breadcrumb.dart';
import '../models/site_visit.dart';
import '../models/time_entry.dart';
import '../services/time_entry_service.dart';
import 'auth_provider.dart';

final timeEntryServiceProvider =
    Provider<TimeEntryService>((ref) => TimeEntryService());

/// Every time entry (manager Hours screen). Gated on sign-in
/// so signing out stays silent; the rules deny non-managers
/// the read anyway.
final allTimeEntriesProvider = StreamProvider<List<TimeEntry>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.watch(timeEntryServiceProvider).watchAllEntries();
});

/// The signed-in worker's own entries (shown on the Hours
/// screen and their profile). Gated on sign-in like the other
/// worker providers.
final myTimeEntriesProvider = StreamProvider<List<TimeEntry>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.watch(timeEntryServiceProvider).watchEntriesForUser(user.id);
});

/// The signed-in worker's open entry, if they are clocked in.
final openTimeEntryProvider = StreamProvider<TimeEntry?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  return ref.watch(timeEntryServiceProvider).watchOpenEntry(user.id);
});

/// One worker's entries, for the profile screen. A family so
/// an admin/manager can read another worker's history — the
/// rules allow admin/manager reads of any entry. Sorted in
/// Dart by the service (no composite index).
final entriesForUserProvider =
    StreamProvider.family<List<TimeEntry>, String>((ref, uid) {
  return ref.watch(timeEntryServiceProvider).watchEntriesForUser(uid);
});

/// One worker's open entry, for the profile screen. Null when
/// they are not clocked in.
final openEntryForUserProvider =
    StreamProvider.family<TimeEntry?, String>((ref, uid) {
  return ref.watch(timeEntryServiceProvider).watchOpenEntry(uid);
});

/// One entry's route trail (breadcrumbs), oldest first, for
/// the map screen. Read rules match the entry itself (owner
/// or admin/manager), so no extra gating here.
final breadcrumbsProvider =
    StreamProvider.family<List<Breadcrumb>, String>((ref, entryId) {
  return ref.watch(timeEntryServiceProvider).watchBreadcrumbs(entryId);
});

/// One entry's site visits (the day's moves), oldest arrival
/// first, for the profile Clock-in tab and the map screen.
/// Read rules match the entry itself (owner or
/// admin/manager), so no extra gating here.
final visitsForEntryProvider =
    StreamProvider.family<List<SiteVisit>, String>((ref, entryId) {
  return ref.watch(timeEntryServiceProvider).watchVisits(entryId);
});

/// Open entries clocked in TODAY, keyed by userId. An open
/// entry from an earlier day is stale (the auto-close function
/// should have closed it) and does not count as clocked in.
/// The entry's stored `date` (device-local yyyy-MM-dd) is the
/// day check. `entries` is newest-first (as watchAllEntries
/// returns), so the first open entry per user wins.
Map<String, TimeEntry> todayOpenEntries(List<TimeEntry> entries, DateTime now) {
  final today = DateFormat('yyyy-MM-dd').format(now);
  final out = <String, TimeEntry>{};
  for (final e in entries) {
    if (e.isOpen && e.date == today) {
      out.putIfAbsent(e.userId, () => e);
    }
  }
  return out;
}

/// Today's open entries for the whole crew (Team screen).
/// One capped stream, filtered in Dart — same source as the
/// Hours screen, so no new index is needed. Managers only:
/// the Team tab is admin/manager-only and the rules deny
/// this read to anyone else.
final todayOpenEntriesProvider = StreamProvider<Map<String, TimeEntry>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value({});
  return ref
      .watch(timeEntryServiceProvider)
      .watchAllEntries()
      .map((list) => todayOpenEntries(list, DateTime.now()));
});
