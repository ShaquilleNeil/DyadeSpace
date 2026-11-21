import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/client_share.dart';
import '../models/site.dart';

/// Tokens are random, unguessable, URL-safe strings. 32
/// characters over a 62-character alphabet (~190 bits) — not
/// guessable, and short enough to paste into a message.
const _tokenAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
const int clientShareTokenLength = 32;

/// A fresh token. [random] is injectable so tests can assert
/// the shape deterministically; production always uses
/// [Random.secure].
String newClientShareToken([Random? random]) {
  final r = random ?? Random.secure();
  return String.fromCharCodes(List.generate(
      clientShareTokenLength,
      (_) => _tokenAlphabet.codeUnitAt(r.nextInt(_tokenAlphabet.length))));
}

/// The public client-share URL for a token. On web this is the
/// app's own origin (so the link works on the deployed host,
/// whatever it is); anywhere else it falls back to the
/// production host.
String clientShareUrl(String token) {
  final origin =
      kIsWeb ? Uri.base.origin : 'https://app.dyademanagement.com';
  return '$origin/client/$token';
}

final clientShareServiceProvider = Provider<ClientShareService>(
  (ref) => ClientShareService(),
);

/// Creates, revokes and reads client share links, and fetches
/// the public progress view for a token.
///
/// Security shape (do not loosen without a review):
/// - The share doc lives at `clientShares/{token}`; the rules
///   allow an unauthenticated `get` of that one doc only (the
///   token is the capability) and admin/manager create/update/
///   delete. No `list`.
/// - The site/tasks/stages collections are NEVER opened to the
///   public. The progress payload comes from the `getClientShare`
///   callable (functions/index.js — Admin SDK, validates the
///   token and the revoked flag server-side, then returns only
///   public-safe fields). If the callable is not deployed yet,
///   the public view shows a load failure instead of leaking
///   data through a widened rule.
class ClientShareService {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  ClientShareService({
    FirebaseFirestore? db,
    FirebaseFunctions? functions,
  })  : _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  CollectionReference<Map<String, dynamic>> get _shares =>
      _db.collection('clientShares');

  /// The active (non-revoked) shares for one site, newest
  /// first. Admin/manager only — the rules deny anyone else.
  Stream<List<ClientShare>> watchSharesForSite(String siteId) {
    return _shares
        .where('siteId', isEqualTo: siteId)
        .where('revoked', isEqualTo: false)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(ClientShare.fromFirestore).toList();
      list.sort((a, b) {
        final ca = a.createdAt;
        final cb = b.createdAt;
        if (ca == null && cb == null) return 0;
        if (ca == null) return 1;
        if (cb == null) return -1;
        return cb.compareTo(ca);
      });
      return list;
    });
  }

  /// Creates a fresh share link for a site. Any previous active
  /// link for the site is revoked first, so there is exactly
  /// one live link per site.
  Future<ClientShare> createShare({
    required Site site,
    required String createdBy,
  }) async {
    final existing = await _shares
        .where('siteId', isEqualTo: site.id)
        .where('revoked', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final doc in existing.docs) {
      batch.update(doc.reference, {
        'revoked': true,
        'revokedAt': FieldValue.serverTimestamp(),
      });
    }
    final token = newClientShareToken();
    final share = ClientShare(
      token: token,
      siteId: site.id,
      siteName: site.name,
      createdBy: createdBy,
    );
    batch.set(_shares.doc(token), share.toMap());
    await batch.commit();
    return share;
  }

  /// Revokes one link. The token's public view stops loading
  /// immediately; the doc is kept (audit trail) rather than
  /// deleted.
  Future<void> revokeShare(String token) async {
    await _shares.doc(token).update({
      'revoked': true,
      'revokedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Revokes the site's current link (if any) and creates a
  /// fresh one — the old URL dies, the new one is returned.
  Future<ClientShare> regenerateShare({
    required Site site,
    required String createdBy,
  }) async {
    return createShare(site: site, createdBy: createdBy);
  }

  /// The public progress payload for a token, via the
  /// `getClientShare` callable. No auth needed: the function
  /// validates the token (exists + not revoked) server-side
  /// and returns only public-safe fields. Throws when the
  /// token is invalid/revoked or the callable is unavailable —
  /// the screen turns that into the "link not valid" state.
  Future<ClientSiteProgress> fetchPublicProgress(String token) async {
    final result = await _functions
        .httpsCallable('getClientShare')
        .call({'token': token});
    final data = result.data;
    if (data is! Map) {
      throw StateError('getClientShare returned an unexpected payload');
    }
    return ClientSiteProgress.fromMap(
        Map<String, dynamic>.from(data));
  }
}
