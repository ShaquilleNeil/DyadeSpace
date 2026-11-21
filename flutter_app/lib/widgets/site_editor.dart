import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/site.dart';
import '../providers/locale_provider.dart';
import '../services/location_service.dart';
import '../theme/app_tokens.dart';

/// The site add/edit dialog, shared by the phone Sites screen
/// and the web control center's Sites section — one
/// implementation so both stay identical. GPS for the clock-in
/// check is stored once per site; "Use my location" fills the
/// coordinates from a single fix taken while standing on the
/// site. Fence radius is whole metres, 10–5000 m; empty or out
/// of range means "not set" (the 100 m default applies). A half
/// coordinate pair is useless for the radius check, so both
/// coordinates are kept or neither.
Future<void> showSiteEditor(
    BuildContext context, WidgetRef ref, Site? existing) async {
  final s = ref.read(stringsProvider);
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final addressCtrl =
      TextEditingController(text: existing?.address ?? '');
  final latCtrl = TextEditingController(
      text: existing?.lat == null ? '' : '${existing!.lat}');
  final lngCtrl = TextEditingController(
      text: existing?.lng == null ? '' : '${existing!.lng}');
  final radiusCtrl = TextEditingController(
      text: existing?.radiusMeters == null
          ? ''
          : '${existing!.radiusMeters!.round()}');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(existing == null ? s.addSite : s.editSite),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: s.name),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: InputDecoration(labelText: s.address),
              ),
              const SizedBox(height: 16),
              Text(
                s.siteLocation,
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                s.siteLocationHint,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTokens.of(ctx).textTertiary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: latCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration:
                          InputDecoration(labelText: s.siteLatitude),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: lngCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration:
                          InputDecoration(labelText: s.siteLongitude),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: radiusCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: s.siteRadius,
                  hintText: s.siteRadiusHint,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.my_location, size: 18),
                  label: Text(s.siteUseMyLocation),
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    final fix = await LocationService().currentFix();
                    if (fix == null) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                              content:
                                  Text(s.clockInLocationUnavailable)),
                        );
                      }
                      return;
                    }
                    setDialogState(() {
                      latCtrl.text = '${fix.lat}';
                      lngCtrl.text = '${fix.lng}';
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () async {
                // No coordinates: clock-ins at this site can
                // never be verified. Require coordinates unless
                // the manager explicitly confirms the site is
                // location-less — a blank lat/lng must never
                // save silently any more.
                final lat =
                    double.tryParse(latCtrl.text.trim());
                final lng =
                    double.tryParse(lngCtrl.text.trim());
                if (lat == null || lng == null) {
                  final saveAnyway = await showDialog<bool>(
                    context: ctx,
                    builder: (c2) => AlertDialog(
                      // TODO(l10n): move to AppStrings.
                      title: const Text('No GPS location'),
                      content: const Text(
                          'This site has no GPS coordinates, so '
                          'clock-ins here can never be verified. '
                          'Save it without a location?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(c2, false),
                            child: Text(s.cancel)),
                        FilledButton(
                            onPressed: () => Navigator.pop(c2, true),
                            // TODO(l10n): move to AppStrings.
                            child: const Text('Save without location')),
                      ],
                    ),
                  );
                  if (saveAnyway != true) return;
                }
                Navigator.pop(ctx, true);
              },
              // The theme gives every FilledButton an infinite minimum
              // width — bound it to its content (same fix as the
              // topbar button).
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
              ),
              child: Text(s.save)),
        ],
      ),
    ),
  );
  if (ok != true) return;
  if (nameCtrl.text.trim().isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.siteNeedsName)),
      );
    }
    return;
  }
  final lat = double.tryParse(latCtrl.text.trim());
  final lng = double.tryParse(lngCtrl.text.trim());
  final radius = double.tryParse(radiusCtrl.text.trim());
  final site = Site(
    id: existing?.id ?? '',
    name: nameCtrl.text.trim(),
    address: addressCtrl.text.trim(),
    lat: lat != null && lng != null ? lat : null,
    lng: lat != null && lng != null ? lng : null,
    radiusMeters:
        radius != null && radius >= 10 && radius <= 5000 ? radius : null,
  );
  try {
    final sites = FirebaseFirestore.instance.collection('sites');
    if (existing == null) {
      await sites.add(site.toMap());
    } else {
      await sites.doc(site.id).update(site.toMap());
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.siteSaveFailed('$e'))),
      );
    }
    return;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.siteSaved)),
    );
  }
}

/// Deletes a site after confirming. A site that still has tasks
/// cannot be deleted (the button explains why) — tasks would be
/// orphaned otherwise. The same block applies to roadmap
/// stages, units, and open material requests: deleting would
/// leave them pointing at a site that no longer exists, and
/// blocking (rather than cascade-deleting) keeps the site's
/// history — hours, reports — intact. Shared by the phone Sites
/// screen and the web control center's Sites section.
Future<void> deleteSite(
    BuildContext context, WidgetRef ref, Site site) async {
  final s = ref.read(stringsProvider);
  try {
    final used = await FirebaseFirestore.instance
        .collection('tasks')
        .where('siteId', isEqualTo: site.id)
        .limit(1)
        .get();
    if (used.docs.isNotEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.siteHasTasks)),
        );
      }
      return;
    }
    // Stages, units, and open requests block the delete too.
    // (Single-field queries + Dart filtering on purpose: no
    // composite indexes at this crew size.)
    final blockers = <String>[];
    final stages = await FirebaseFirestore.instance
        .collection('stages')
        .where('siteId', isEqualTo: site.id)
        .limit(1)
        .get();
    if (stages.docs.isNotEmpty) blockers.add('roadmap stages');
    final units = await FirebaseFirestore.instance
        .collection('units')
        .where('siteId', isEqualTo: site.id)
        .limit(1)
        .get();
    if (units.docs.isNotEmpty) blockers.add('units');
    final requests = await FirebaseFirestore.instance
        .collection('materialRequests')
        .where('siteId', isEqualTo: site.id)
        .limit(100)
        .get();
    const openStatuses = {'requested', 'approved', 'onRun'};
    if (requests.docs.any((d) =>
        openStatuses.contains(d.data()['status'] as String?))) {
      blockers.add('open material requests');
    }
    if (blockers.isNotEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // TODO(l10n): move to AppStrings.
            content: Text(
                'This site still has ${blockers.join(', ')} — '
                'remove them first.'),
          ),
        );
      }
      return;
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.siteSaveFailed('$e'))),
      );
    }
    return;
  }
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.delete),
      content: Text(s.deleteSiteConfirm(site.name)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel)),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            // The theme gives every FilledButton an infinite minimum
            // width — bound it to its content (same fix as the
            // topbar button).
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
            ),
            child: Text(s.delete)),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await FirebaseFirestore.instance
        .collection('sites')
        .doc(site.id)
        .delete();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.siteSaveFailed('$e'))),
      );
    }
    return;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.siteDeleted)),
    );
  }
}
