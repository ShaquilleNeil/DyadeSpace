import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_user.dart';

/// Email sign-in. DyadeSpace is INVITE-ONLY: a person can only create
/// an account if an admin/manager first created a document for their
/// email in the `invites` collection (People screen does that).
/// The invite carries the role the new user gets.
class AuthService {
  // The Firebase singletons resolve lazily (getters below),
  // not in the constructor: a test can construct this service
  // with overrides — or with none at all — without Firebase
  // being initialised, and only the methods it actually calls
  // touch the real SDKs.
  final FirebaseAuth? _authOverride;
  final FirebaseFirestore? _dbOverride;
  final FirebaseFunctions? _functionsOverride;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;
  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instance;

  AuthService({FirebaseAuth? auth, FirebaseFirestore? db,
      FirebaseFunctions? functions})
      : _authOverride = auth,
        _dbOverride = db,
        _functionsOverride = functions;

  /// Stream of the signed-in AppUser (null when signed out).
  /// Reads the profile from `users/{uid}`.
  ///
  /// A permission-denied from the profile listener during an auth
  /// transition (sign-out revokes the token while the listener is
  /// still attached) is treated as "signed out" (null), never as a
  /// stream error - otherwise the root would show an error wall.
  Stream<AppUser?> watchCurrentUser() {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(null);
      return _db
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .map((doc) => doc.exists ? AppUser.fromFirestore(doc) : null)
          .transform(
            StreamTransformer<AppUser?, AppUser?>.fromHandlers(
              handleError: (error, stackTrace, sink) {
                if (error is FirebaseException &&
                    error.code == 'permission-denied') {
                  sink.add(null);
                  sink.close();
                } else {
                  sink.addError(error, stackTrace);
                }
              },
            ),
          );
    });
  }

  Future<void> signIn(String email, String password) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Sends the Firebase password-reset email to [email].
  /// Throws FirebaseAuthException (invalid-email, user-not-found,
  /// ...) — the sign-in screen maps the code to a friendly
  /// message via AppStrings.authError.
  Future<void> forgotPassword(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Creates an account ONLY if an invite exists for this email.
  /// Throws a StateError with a machine-readable code otherwise
  /// ('no-invite', 'empty-name') — the sign-in screen maps the
  /// code to a localised message, never the raw text.
  ///
  /// Order matters: the Firestore rules only let a SIGNED-IN user
  /// read their own invite (matched by email), so we create the
  /// Auth account first, then check the invite.
  ///
  /// Orphan guard (audit P1): EVERYTHING after
  /// createUserWithEmailAndPassword runs inside one try/catch,
  /// and any failure deletes the just-created Auth user before
  /// rethrowing — a findInvite throw, a users-doc write failure
  /// or an invite-marking failure must never strand an Auth
  /// account with no profile (retry would fail
  /// email-already-in-use and sign-in would loop silently to
  /// the sign-in screen). The delete itself is best-effort: if
  /// it fails we still rethrow the original error.
  ///
  /// Emails are lowercased everywhere (create, lookup, stored
  /// profile): invite storage used to be case-inconsistent, so
  /// `John@Example.com` invited and `john@example.com` signing
  /// up found no invite.
  Future<void> signUpWithInvite({
    required String email,
    required String password,
    required String name,
    String phone = '',
  }) async {
    final emailNorm = email.trim().toLowerCase();
    if (name.trim().isEmpty) {
      throw StateError('empty-name');
    }
    final cred = await _auth.createUserWithEmailAndPassword(
      email: emailNorm,
      password: password,
    );
    try {
      final invite = await findInvite(emailNorm);
      if (invite == null) {
        throw StateError('no-invite');
      }
      final user = AppUser(
        id: cred.user!.uid,
        name: name.trim(),
        email: emailNorm,
        phone: phone,
        role: userRoleFromString(invite['role'] as String?),
        language: 'en',
      );
      await _db.collection('users').doc(user.id).set(user.toMap());
      // Mark every pending invite for this email as used so none
      // of them lingers in the pending list. (The new user cannot
      // delete invite docs - the rules only allow admin/manager
      // deletes - but they may update their own invites to
      // 'accepted'.)
      final pending = await _db
          .collection('invites')
          .where('email', isEqualTo: emailNorm)
          .where('status', isEqualTo: 'pending')
          .get();
      for (final doc in pending.docs) {
        await doc.reference.update({
          'status': 'accepted',
          'acceptedBy': user.id,
        });
      }
    } catch (e) {
      try {
        await cred.user?.delete();
      } catch (_) {
        // Best-effort cleanup only: the original failure is
        // what the caller reports.
      }
      rethrow;
    }
  }

  /// Returns the pending invite for an email, or null.
  /// The lookup is lowercased (and trimmed) to match the
  /// lowercased emails stored by createInvite/createInvitesBulk.
  Future<Map<String, dynamic>?> findInvite(String email) async {
    final snap = await _db
        .collection('invites')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return {'id': snap.docs.first.id, ...snap.docs.first.data()};
  }

  /// Admin/manager side: create an invite document.
  /// Throws StateError('already-member') if the email already has
  /// an account, StateError('already-invited') if a pending invite
  /// already exists for it - the People screen turns those codes
  /// into friendly messages instead of creating duplicates.
  /// Throws StateError('admin-invite-requires-admin') when the
  /// invite is for role 'admin' and the inviter (looked up by
  /// [invitedBy] uid) is not an admin — a manager must never be
  /// able to invite an admin account. The email is lowercased
  /// before storage so lookups match regardless of case.
  /// The invite UI must also hide the admin option for managers
  /// (People screen / bulk-invite sheet); this check is the
  /// backstop for any caller that does not.
  Future<void> createInvite({
    required String email,
    required UserRole role,
    required String invitedBy,
  }) async {
    final trimmed = email.trim().toLowerCase();
    if (role == UserRole.admin && !await _isAdmin(invitedBy)) {
      throw StateError('admin-invite-requires-admin');
    }
    final existingUser = await _db
        .collection('users')
        .where('email', isEqualTo: trimmed)
        .limit(1)
        .get();
    if (existingUser.docs.isNotEmpty) {
      throw StateError('already-member');
    }
    if (await findInvite(trimmed) != null) {
      throw StateError('already-invited');
    }
    await _db.collection('invites').add({
      'email': trimmed,
      'role': role.name,
      'status': 'pending',
      'invitedBy': invitedBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// True when the user doc for [uid] has role 'admin'.
  /// Fail-closed: a missing/unreadable doc is not an admin, so
  /// an admin invite from that uid is refused.
  Future<bool> _isAdmin(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final data = doc.data();
      return data != null && data['role'] == UserRole.admin.name;
    } catch (_) {
      return false;
    }
  }

  /// Maximum invites in one bulk import. Anything beyond the
  /// cap is NOT created; the excess emails come back in
  /// [BulkInviteResult.overCap] so the caller can say so
  /// instead of silently dropping them (or hammering
  /// Firestore with an unbounded batch).
  static const maxBulkInvites = 100;

  /// Admin/manager side: create one invite per email in
  /// [emails], all with the same [role]. The list is
  /// lowercased, trimmed and deduped first; the caller is
  /// responsible for format validation (invalid addresses
  /// never reach this method). Each email is checked against
  /// existing accounts and pending invites, so a batch never
  /// duplicates what is already there. Creates go out in
  /// batches of 400 (the Firestore batch limit is 500).
  /// At most [maxBulkInvites] are created per call; the rest
  /// are reported in the result's [BulkInviteResult.overCap].
  /// Throws StateError('admin-invite-requires-admin') for an
  /// admin-role batch from a non-admin inviter.
  Future<BulkInviteResult> createInvitesBulk({
    required List<String> emails,
    required UserRole role,
    required String invitedBy,
  }) async {
    if (role == UserRole.admin && !await _isAdmin(invitedBy)) {
      throw StateError('admin-invite-requires-admin');
    }
    final unique = <String>{
      for (final e in emails) e.trim().toLowerCase(),
    }..remove('');
    // Deterministic order (a Set's iteration order is not
    // stable across runs): the first maxBulkInvites, sorted,
    // are created and the rest are reported as over the cap.
    final sorted = unique.toList()..sort();
    final toCreate = sorted.take(maxBulkInvites).toList();
    final overCap = sorted.skip(maxBulkInvites).toList();
    final created = <String>[];
    final alreadyMember = <String>[];
    final alreadyInvited = <String>[];
    var batch = _db.batch();
    var inBatch = 0;
    Future<void> flush() async {
      if (inBatch == 0) return;
      await batch.commit();
      batch = _db.batch();
      inBatch = 0;
    }

    for (final email in toCreate) {
      final existingUser = await _db
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (existingUser.docs.isNotEmpty) {
        alreadyMember.add(email);
        continue;
      }
      if (await findInvite(email) != null) {
        alreadyInvited.add(email);
        continue;
      }
      batch.set(_db.collection('invites').doc(), {
        'email': email,
        'role': role.name,
        'status': 'pending',
        'invitedBy': invitedBy,
        'createdAt': FieldValue.serverTimestamp(),
      });
      inBatch++;
      created.add(email);
      if (inBatch >= 400) await flush();
    }
    await flush();
    return BulkInviteResult(
      created: created,
      alreadyMember: alreadyMember,
      alreadyInvited: alreadyInvited,
      overCap: overCap,
    );
  }

  /// Emails from CSV text — a robust whole-document parser.
  /// Unlike a line splitter this honours double-quoted fields
  /// that span newlines (and `""` escapes), strips a UTF-8 BOM
  /// and handles CRLF. The email column is the first column
  /// whose header cell is an email header (`email`, `e-mail`,
  /// `courriel`, `correo`, case-insensitive); without one, the
  /// first column that holds an `@` address in any data row.
  /// The first row is skipped when it is a header: it names the
  /// email column, or it holds no `@` anywhere while a later
  /// row does (so a header like `Name,Email Address` — or a
  /// bare first row of names — never becomes an invite).
  /// Only well-formed, lowercased, deduped addresses come back;
  /// everything else is dropped.
  static List<String> parseCsvEmails(String text) {
    final rows = _parseCsvDocument(text);
    if (rows.isEmpty) return [];
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    final headerNames = {'email', 'e-mail', 'courriel', 'correo'};
    final first = rows.first;
    var emailCol = -1;
    for (var i = 0; i < first.length; i++) {
      if (headerNames.contains(first[i].trim().toLowerCase())) {
        emailCol = i;
        break;
      }
    }
    final firstHasAddress =
        first.any((cell) => cell.contains('@'));
    final laterHasAddress = rows
        .skip(1)
        .any((row) => row.any((cell) => cell.contains('@')));
    final firstIsHeader =
        emailCol >= 0 || (!firstHasAddress && laterHasAddress);
    if (emailCol < 0) {
      // No named header: first column holding an '@' address.
      outer:
      for (var r = firstIsHeader ? 1 : 0; r < rows.length; r++) {
        for (var c = 0; c < rows[r].length; c++) {
          if (emailPattern.hasMatch(rows[r][c].trim())) {
            emailCol = c;
            break outer;
          }
        }
      }
      if (emailCol < 0) emailCol = 0;
    }
    final seen = <String>{};
    final emails = <String>[];
    for (var r = firstIsHeader ? 1 : 0; r < rows.length; r++) {
      final row = rows[r];
      if (emailCol >= row.length) continue;
      final email = row[emailCol].trim().toLowerCase();
      if (email.isEmpty || !seen.add(email)) continue;
      if (emailPattern.hasMatch(email)) emails.add(email);
    }
    return emails;
  }

  /// Parses a whole CSV document into rows of fields.
  /// Double-quoted fields may contain commas, newlines and
  /// `""` escapes; bare CR/LF/CRLF all end a row.
  static List<List<String>> _parseCsvDocument(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    var fieldStarted = false;
    void endField() {
      row.add(current.toString().trim());
      current.clear();
      fieldStarted = false;
    }

    var s = text;
    if (s.startsWith('\uFEFF')) s = s.substring(1);
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            current.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          current.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
        fieldStarted = true;
      } else if (ch == ',') {
        endField();
      } else if (ch == '\r' || ch == '\n') {
        if (ch == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
        endField();
        if (row.any((f) => f.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        current.write(ch);
        fieldStarted = true;
      }
    }
    if (inQuotes || fieldStarted || current.isNotEmpty || row.isNotEmpty) {
      endField();
      if (row.any((f) => f.isNotEmpty)) rows.add(row);
    }
    return rows;
  }

  /// Admin/manager side: delete a pending invite (People screen
  /// Revoke action). The rules allow delete only for
  /// admin/manager, which is who sees that screen.
  Future<void> revokeInvite(String inviteId) =>
      _db.collection('invites').doc(inviteId).delete();

  /// Pending invites (People screen). Sorted by email in Dart -
  /// createdAt is a server timestamp and can be briefly null.
  Stream<List<Map<String, dynamic>>> pendingInvites() {
    return _db
        .collection('invites')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
      list.sort((a, b) =>
          (a['email'] as String? ?? '').compareTo(b['email'] as String? ?? ''));
      return list;
    });
  }

  /// All user profiles (People screen, assignee pickers).
  /// Returns EVERYONE, active and deactivated: the admin
  /// People screen needs the deactivated members too (to show
  /// them and re-activate). Pickers that message people — the
  /// new-chat sheet and the broadcast recipient list — must
  /// use [activeUsers] instead so a deactivated user can never
  /// be DM'd or broadcast to.
  Stream<List<AppUser>> allUsers() {
    return _db.collection('users').snapshots().map((snap) {
      final list = snap.docs.map(AppUser.fromFirestore).toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  /// Active user profiles only, for pickers that reach people
  /// (new chat, broadcast recipients, assignee pickers).
  /// Same ordering as [allUsers].
  Stream<List<AppUser>> activeUsers() {
    return allUsers().map(
      (users) => users.where((u) => u.active).toList(),
    );
  }

  Future<void> signOut() => _auth.signOut();

  /// Deletes the caller's OWN account, server-side, through
  /// the `deleteMyAccount` callable Cloud Function. The server
  /// removes the Auth user, the users/{uid} doc, the profile
  /// photo and the user's notifications. It does NOT delete
  /// time entries (payroll records), tasks or chat messages —
  /// those are shared records and stay, with the name on them
  /// showing as "Former member". Throws on failure — the
  /// caller shows an error and stays signed in. Deleting
  /// server-side avoids the client `user.delete()` recent-
  /// login requirement, so no re-auth flow is needed.
  ///
  /// Partial failure: the function deletes the profile doc
  /// BEFORE the Auth user, so a failure mid-call can leave an
  /// Auth account with no profile (sign-in then yields a null
  /// profile). The caller must NOT sign out on failure — the
  /// user stays signed in and retries the same call, which
  /// completes the deletion (the doc/photo deletes are
  /// idempotent). The function still has orphaned-reference
  /// cleanup to do — see the audit report for the full list
  /// (teams memberIds, chat/task photos, invites, FCM topics,
  /// and every profile-photo file under profilePhotos/<uid>/).
  Future<void> deleteMyAccount() async {
    await _functions.httpsCallable('deleteMyAccount').call();
  }

  /// Sets the profile photo URL on a user doc. The caller
  /// uploads the file first; this only writes the URL. The
  /// Firestore rules let a user update their own doc (the role
  /// field untouched) and admins/managers update anyone's.
  Future<void> updatePhotoUrl({
    required String uid,
    required String? photoUrl,
  }) =>
      _db.collection('users').doc(uid).update({'photoUrl': photoUrl});

  /// Changes a user's role. Admin-only in the UI (the role
  /// dropdown on WorkerProfileScreen) and in practice: the
  /// Firestore rules let an admin/manager update anyone's doc,
  /// but a plain self-update must keep the role unchanged, so
  /// this must never be called for the viewer's own profile.
  Future<void> updateRole({
    required String uid,
    required UserRole role,
  }) =>
      _db.collection('users').doc(uid).update({'role': role.name});

  /// Replaces the notification prefs map on a user doc. The
  /// caller passes the full map (Settings screen); missing
  /// keys read as ON. Same rules as updatePhotoUrl.
  Future<void> updateNotifPrefs({
    required String uid,
    required Map<String, bool> prefs,
  }) =>
      _db.collection('users').doc(uid).update({'notifPrefs': prefs});
}

/// Result of a bulk invite: which emails got an invite, and
/// which were skipped, with the reason for each skip.
/// [overCap] holds the emails beyond [AuthService.maxBulkInvites]
/// that were NOT invited in this call — the caller must surface
/// them (they are not silently dropped).
class BulkInviteResult {
  final List<String> created;
  final List<String> alreadyMember;
  final List<String> alreadyInvited;
  final List<String> overCap;
  const BulkInviteResult({
    this.created = const [],
    this.alreadyMember = const [],
    this.alreadyInvited = const [],
    this.overCap = const [],
  });
}
