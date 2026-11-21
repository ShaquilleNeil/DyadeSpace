import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../models/time_entry.dart';
import '../providers/locale_provider.dart';
import '../providers/time_entries_provider.dart';
import '../theme/app_tokens.dart';
import '../widgets/site_visits_list.dart';

/// Where a worker clocked in or out: the event's GPS pin on an
/// OpenStreetMap map (flutter_map, no API key, no native
/// setup), plus the worker, site, date/time and Verified /
/// Flagged badge. When the entry has both a clock-in and a
/// clock-out location, a toggle switches the pin between them.
/// "Open in Maps" hands the shown coordinates to Google Maps.
/// When the shown event has no coordinates, the details still
/// show and the map is replaced by a note — nothing is
/// invented.
class ClockLocationScreen extends ConsumerStatefulWidget {
  final TimeEntry entry;

  /// False opens on the clock-in pin, true on the clock-out pin.
  final bool isClockOut;

  const ClockLocationScreen({
    super.key,
    required this.entry,
    this.isClockOut = false,
  });

  @override
  ConsumerState<ClockLocationScreen> createState() =>
      _ClockLocationScreenState();
}

class _ClockLocationScreenState extends ConsumerState<ClockLocationScreen> {
  late bool _showClockOut;

  @override
  void initState() {
    super.initState();
    _showClockOut = widget.isClockOut;
  }

  TimeEntry get _entry => widget.entry;

  bool get _hasOut =>
      _entry.clockOutAt != null &&
      _entry.clockOutLat != null &&
      _entry.clockOutLng != null;

  double? get _lat => _showClockOut ? _entry.clockOutLat : _entry.clockInLat;
  double? get _lng => _showClockOut ? _entry.clockOutLng : _entry.clockInLng;
  DateTime get _at => _showClockOut
      ? (_entry.clockOutAt ?? _entry.clockInAt)
      : _entry.clockInAt;
  Future<void> _openInMaps(AppStrings s) async {
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) return;
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    var launched = false;
    if (await canLaunchUrl(uri)) {
      launched = await launchUrl(uri);
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.openInMapsFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final lat = _lat;
    final lng = _lng;
    final flagged = _entry.flagged;
    // Route trail: breadcrumbs while clocked in (empty when the
    // entry predates tracking or no point was ever recorded).
    // Admins/managers see any worker's trail; a worker sees
    // their own — the rules enforce the same split.
    final crumbs = ref.watch(breadcrumbsProvider(_entry.id)).valueOrNull ?? [];
    final trail = crumbs.map((c) => LatLng(c.lat, c.lng)).toList();
    // The day's site visits (see SiteVisitsList below).
    final visits =
        ref.watch(visitsForEntryProvider(_entry.id)).valueOrNull ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _showClockOut ? s.clockOutLocation : s.clockInLocation,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          if (_hasOut) ...[
            SegmentedButton<bool>(
              segments: [
                ButtonSegment<bool>(value: false, label: Text(s.clockIn)),
                ButtonSegment<bool>(value: true, label: Text(s.clockOut)),
              ],
              selected: {_showClockOut},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  setState(() => _showClockOut = selection.first);
                }
              },
            ),
            const SizedBox(height: 16),
          ],
          Container(
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(AppTokens.cardRadius),
              border: Border.all(color: tokens.border),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _entry.userName,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _entry.siteName.isEmpty ? s.noSite : _entry.siteName,
                  style: TextStyle(
                    fontSize: 14,
                    color: tokens.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('EEE MMM d, yyyy').format(_at)} · ${DateFormat('HH:mm').format(_at)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:
                            (flagged ? tokens.statusBlocked : tokens.statusDone)
                                .withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        flagged
                            ? '${s.hoursFlagged}: ${s.flagReasonLabel(_entry.flagReason)}'
                            : s.hoursVerified,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: flagged
                              ? tokens.statusBlocked
                              : tokens.statusDone,
                        ),
                      ),
                    ),
                    if (_entry.auto)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          s.autoTag,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tokens.accentText,
                          ),
                        ),
                      ),
                  ],
                ),
                if (lat != null && lng != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: tokens.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (trail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${s.routeTrail} · ${trail.length}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.textSecondary,
                ),
              ),
            ),
          if (lat != null && lng != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.cardRadius),
              child: SizedBox(
                height: 380,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(lat, lng),
                    initialZoom: 16,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.dyadespace_scaffold',
                    ),
                    if (trail.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: trail,
                            strokeWidth: 4,
                            color: tokens.accentText,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(lat, lng),
                          width: 48,
                          height: 48,
                          child: Icon(
                            Icons.location_on,
                            size: 44,
                            color: tokens.accentText,
                          ),
                        ),
                        // Trail ends: green = where the route
                        // started, red = where it ended (last
                        // point while clocked in). Only when the
                        // trail has more than one point.
                        if (trail.length > 1)
                          Marker(
                            point: trail.first,
                            width: 32,
                            height: 32,
                            child: Icon(
                              Icons.flag,
                              size: 28,
                              color: tokens.statusDone,
                            ),
                          ),
                        if (trail.length > 1)
                          Marker(
                            point: trail.last,
                            width: 32,
                            height: 32,
                            child: Icon(
                              Icons.flag,
                              size: 28,
                              color: tokens.danger,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.map_outlined, size: 20),
                label: Text(s.openInMaps),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
                onPressed: () => _openInMaps(s),
              ),
            ),
          ] else
            Text(
              s.noLocationForEntry,
              style: TextStyle(
                fontSize: 14,
                color: tokens.textSecondary,
              ),
            ),
          // The day's site visits, under the map: where the
          // worker actually was, in arrival order. Nothing
          // renders when the entry has no visits.
          if (visits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.visits,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tokens.textSecondary,
                    ),
                  ),
                  SiteVisitsList(
                    visits: visits,
                    entryClockOutAt: _entry.clockOutAt,
                    strings: s,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
