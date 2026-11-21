import 'package:dyadespace/models/time_entry.dart';
import 'package:dyadespace/utils/week_hours.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// Unit tests for the shared week-hours computation: the week
/// is Monday–Sunday, and the total counts closed entries'
/// hours plus an open entry's live time so far. Pure Dart, no
/// Firebase, no device.
void main() {
  String dateStr(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  TimeEntry entry({
    required String id,
    required String userId,
    required DateTime clockInAt,
    DateTime? clockOutAt,
    double? hours,
    bool flagged = false,
  }) =>
      TimeEntry(
        id: id,
        userId: userId,
        userName: 'Worker $userId',
        siteId: 'site-1',
        siteName: 'Maple Court',
        date: dateStr(clockInAt),
        clockInAt: clockInAt,
        clockOutAt: clockOutAt,
        hours: hours,
        flagged: flagged,
      );

  test('weekStartFor is the Monday of the same week', () {
    // 2026-11-16 is a Monday; 2026-11-18 a Wednesday;
    // 2026-11-22 a Sunday.
    expect(weekStartFor(DateTime(2026, 11, 16)), DateTime(2026, 11, 16));
    expect(weekStartFor(DateTime(2026, 11, 18)), DateTime(2026, 11, 16));
    expect(weekStartFor(DateTime(2026, 11, 22)), DateTime(2026, 11, 16));
    expect(weekStartFor(DateTime(2026, 11, 23)), DateTime(2026, 11, 23));
  });

  test('entriesInWeek keeps Monday–Sunday, drops the rest', () {
    final weekStart = DateTime(2026, 11, 16); // Monday
    final entries = [
      entry(
          id: 'prev-sun',
          userId: 'u1',
          clockInAt: DateTime(2026, 11, 15, 8),
          clockOutAt: DateTime(2026, 11, 15, 16),
          hours: 8),
      entry(
          id: 'mon',
          userId: 'u1',
          clockInAt: DateTime(2026, 11, 16, 8),
          clockOutAt: DateTime(2026, 11, 16, 16),
          hours: 8),
      entry(
          id: 'sun',
          userId: 'u1',
          clockInAt: DateTime(2026, 11, 22, 8),
          clockOutAt: DateTime(2026, 11, 22, 12),
          hours: 4),
      entry(
          id: 'next-mon',
          userId: 'u1',
          clockInAt: DateTime(2026, 11, 23, 8),
          clockOutAt: DateTime(2026, 11, 23, 16),
          hours: 8),
    ];
    final inWeek = entriesInWeek(entries, weekStart);
    expect(inWeek.map((e) => e.id), ['mon', 'sun']);
  });

  test('week total sums closed entries, flagged included', () {
    final weekStart = DateTime(2026, 11, 16);
    final entries = [
      entry(
          id: 'a',
          userId: 'u1',
          clockInAt: DateTime(2026, 11, 16, 8),
          clockOutAt: DateTime(2026, 11, 16, 16),
          hours: 8),
      entry(
          id: 'b',
          userId: 'u1',
          clockInAt: DateTime(2026, 11, 17, 8),
          clockOutAt: DateTime(2026, 11, 17, 12),
          hours: 4,
          flagged: true),
      entry(
          id: 'other-week',
          userId: 'u1',
          clockInAt: DateTime(2026, 11, 9, 8),
          clockOutAt: DateTime(2026, 11, 9, 16),
          hours: 8),
    ];
    expect(weekTotalIncludingLive(entries, weekStart), 12);
  });

  test('week total falls back to clock times when server hours are missing',
      () {
    final weekStart = DateTime(2026, 11, 16);
    final entries = [
      entry(
        id: 'a',
        userId: 'u1',
        clockInAt: DateTime(2026, 11, 16, 8),
        clockOutAt: DateTime(2026, 11, 16, 11, 30),
        hours: null,
      ),
    ];
    expect(weekTotalIncludingLive(entries, weekStart), 3.5);
  });

  test('week total includes an open entry\'s live time so far', () {
    final now = DateTime.now();
    final weekStart = weekStartFor(now);
    final entries = [
      entry(
        id: 'open',
        userId: 'u1',
        clockInAt: now.subtract(const Duration(minutes: 90)),
      ),
    ];
    // 90 minutes live ≈ 1.5 h (a minute may tick mid-test).
    expect(weekTotalIncludingLive(entries, weekStart), closeTo(1.5, 0.05));
  });

  test('week total is 0 with no entries in the week', () {
    expect(weekTotalIncludingLive([], DateTime(2026, 11, 16)), 0);
  });

  test('Toronto wall time: UTC noon is 07:00 EST in November', () {
    expect(torontoWallTime(DateTime.utc(2026, 11, 16, 12)),
        DateTime(2026, 11, 16, 7));
    expect(torontoOffsetHours(DateTime.utc(2026, 11, 16, 12)), -5);
  });

  test('Toronto wall time: UTC noon is 08:00 EDT in July', () {
    expect(torontoWallTime(DateTime.utc(2026, 7, 16, 12)),
        DateTime(2026, 7, 16, 8));
    expect(torontoOffsetHours(DateTime.utc(2026, 7, 16, 12)), -4);
  });

  test('Toronto date of a UTC instant just after midnight is the previous day', () {
    // 2026-01-01 04:30 UTC is 2025-12-31 23:30 in Toronto.
    expect(torontoDateStr(DateTime.utc(2026, 1, 1, 4, 30)), '2025-12-31');
  });

  test('a shift crossing midnight splits across the two days/weeks', () {
    // Sunday 2026-11-15 23:00 Toronto to Monday 01:00 Toronto.
    // (Test instants are built in UTC and converted: Toronto
    // is UTC-5 in November, so 23:00 Toronto == 04:00 UTC.)
    final inAt = DateTime.utc(2026, 11, 16, 4, 0);
    final outAt = DateTime.utc(2026, 11, 16, 6, 0);
    final shift = entry(
      id: 'night',
      userId: 'u1',
      clockInAt: inAt,
      clockOutAt: outAt,
      hours: 2,
    );
    // 1 h in the old week (Mon Nov 9), 1 h in the new week.
    expect(entryHoursInWeek(shift, DateTime(2026, 11, 9)), 1);
    expect(entryHoursInWeek(shift, DateTime(2026, 11, 16)), 1);
    expect(
        weekTotalIncludingLive([shift], DateTime(2026, 11, 16)), 1);
    expect(
        weekTotalIncludingLive([shift], DateTime(2026, 11, 9)), 1);
    // And it appears in both weeks' entry lists.
    expect(entriesInWeek([shift], DateTime(2026, 11, 9)).length, 1);
    expect(entriesInWeek([shift], DateTime(2026, 11, 16)).length, 1);
    // Per-day split: 1 h Sunday, 1 h Monday.
    expect(entryHoursOnTorontoDate(shift, DateTime(2026, 11, 15)), 1);
    expect(entryHoursOnTorontoDate(shift, DateTime(2026, 11, 16)), 1);
  });

  test('an entry wholly inside the week still totals its stored hours', () {
    final weekStart = DateTime(2026, 11, 16);
    final entries = [
      entry(
          id: 'a',
          userId: 'u1',
          clockInAt: DateTime.utc(2026, 11, 16, 13, 0),
          clockOutAt: DateTime.utc(2026, 11, 16, 21, 0),
          hours: 8),
    ];
    expect(weekTotalIncludingLive(entries, weekStart), 8);
  });

  test('a shift crossing midnight counts only its part in the week total', () {
    // Monday 2026-11-16 22:00 Toronto (03:00 UTC Tue) to
    // Tuesday 02:00 Toronto (07:00 UTC Tue): 2 h Monday, 2 h
    // Tuesday — the Monday week total is 4 h either way here,
    // so use the Sunday/Monday boundary instead: Sunday
    // 22:00 Toronto to Monday 02:00 Toronto.
    final shift = entry(
      id: 'night',
      userId: 'u1',
      clockInAt: DateTime.utc(2026, 11, 16, 3, 0),
      clockOutAt: DateTime.utc(2026, 11, 16, 7, 0),
      hours: 4,
    );
    expect(weekTotalIncludingLive([shift], DateTime(2026, 11, 16)), 2);
    expect(weekTotalIncludingLive([shift], DateTime(2026, 11, 9)), 2);
  });
}
