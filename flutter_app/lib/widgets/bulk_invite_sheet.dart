import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_tokens.dart';
import 'member_tile.dart';

/// Bulk invite sheet (Team screen, admin/manager only).
/// Two ways in, one role for the whole batch:
/// - Paste: one email per line, or separated by commas.
/// - Import CSV: pick a .csv file; the email column is
///   auto-detected (a header containing "email" wins, else the
///   first column). Google Sheets is NOT integrated — the hint
///   tells the manager to export the sheet as CSV first.
/// Invites are Firestore records only, exactly like the
/// single invite (no email is sent by the app — the mailto
/// button on each pending invite still composes it). After
/// the batch runs, the sheet shows the summary: how many
/// invites were created and which emails were skipped, with
/// the reason for each skip.
Future<void> showBulkInviteSheet(
  BuildContext context,
  WidgetRef ref, {
  required String invitedBy,
}) async {
  // The sheet owns its controllers: they live in the sheet's
  // State and are disposed in State.dispose — never disposed
  // from this function after the sheet closes (a rebuild
  // after the pop would crash on a disposed controller).
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _BulkInviteSheet(invitedBy: invitedBy),
  );
}

enum _BulkTab { paste, csv }

class _BulkInviteSheet extends ConsumerStatefulWidget {
  final String invitedBy;
  const _BulkInviteSheet({required this.invitedBy});

  @override
  ConsumerState<_BulkInviteSheet> createState() => _BulkInviteSheetState();
}

class _BulkInviteSheetState extends ConsumerState<_BulkInviteSheet> {
  final _pasteCtrl = TextEditingController();
  _BulkTab _tab = _BulkTab.paste;
  UserRole _role = UserRole.worker;
  List<String> _csvEmails = [];
  String? _csvFileName;
  BulkInviteResult? _result;
  List<String> _invalid = [];
  bool _busy = false;

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Splits pasted text on commas, newlines and semicolons,
  /// trims, lowercases and dedupes. Returns (valid, invalid).
  static ({List<String> valid, List<String> invalid}) parseEmailList(
      String raw) {
    final seen = <String>{};
    final valid = <String>[];
    final invalid = <String>[];
    for (final part in raw.split(RegExp(r'[,\n;]+'))) {
      final email = part.trim().toLowerCase();
      if (email.isEmpty) continue;
      if (!seen.add(email)) continue;
      if (_emailPattern.hasMatch(email)) {
        valid.add(email);
      } else {
        invalid.add(email);
      }
    }
    return (valid: valid, invalid: invalid);
  }

  /// One CSV line, respecting double-quoted fields.
  static List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
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
      } else if (ch == ',') {
        fields.add(current.toString());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    fields.add(current.toString());
    return fields.map((f) => f.trim()).toList();
  }

  /// Emails from CSV text: the email column is the first
  /// column whose header contains "email" (case-insensitive);
  /// without such a header the first column is used and the
  /// first row counts as data. Invalid addresses are dropped
  /// here and reported by the caller.
  static List<String> parseCsvEmails(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return [];
    final header = _parseCsvLine(lines.first);
    var emailCol = 0;
    var firstIsHeader = false;
    for (var i = 0; i < header.length; i++) {
      if (header[i].toLowerCase().contains('email')) {
        emailCol = i;
        firstIsHeader = true;
        break;
      }
    }
    final emails = <String>[];
    for (var r = firstIsHeader ? 1 : 0; r < lines.length; r++) {
      final fields = _parseCsvLine(lines[r]);
      if (emailCol >= fields.length) continue;
      final email = fields[emailCol].trim().toLowerCase();
      if (email.isEmpty) continue;
      if (_emailPattern.hasMatch(email)) emails.add(email);
    }
    return emails;
  }

  Future<void> _pickCsv() async {
    final s = ref.read(stringsProvider);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes);
      final emails = parseCsvEmails(text);
      if (!mounted) return;
      setState(() {
        _csvEmails = emails.toSet().toList();
        _csvFileName = file.name;
        _result = null;
        _invalid = [];
      });
      if (emails.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.bulkInviteNoValidEmails)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(stringsProvider).bulkInviteFileReadFailed)),
      );
    }
  }

  Future<void> _createInvites() async {
    final s = ref.read(stringsProvider);
    final parsed = _tab == _BulkTab.paste
        ? parseEmailList(_pasteCtrl.text)
        : (valid: _csvEmails, invalid: <String>[]);
    if (parsed.valid.isEmpty) {
      setState(() => _invalid = parsed.invalid);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.bulkInviteNoValidEmails)),
      );
      return;
    }
    setState(() {
      _busy = true;
      _invalid = parsed.invalid;
    });
    try {
      final result =
          await ref.read(authServiceProvider).createInvitesBulk(
                emails: parsed.valid,
                role: _role,
                invitedBy: widget.invitedBy,
              );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.bulkInvite,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SegmentedButton<_BulkTab>(
                segments: [
                  ButtonSegment(
                      value: _BulkTab.paste, label: Text(s.bulkInvitePaste)),
                  ButtonSegment(
                      value: _BulkTab.csv, label: Text(s.bulkInviteImport)),
                ],
                selected: {_tab},
                onSelectionChanged: (sel) {
                  if (sel.isNotEmpty) {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _tab = sel.first;
                      _result = null;
                      _invalid = [];
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              if (_tab == _BulkTab.paste) ...[
                TextField(
                  controller: _pasteCtrl,
                  minLines: 5,
                  maxLines: 10,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: s.bulkInvitePasteHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                Text(
                  s.bulkInviteSheetsHint,
                  style: TextStyle(
                    fontSize: 13,
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: Text(_csvFileName ?? s.bulkInviteChooseFile),
                    onPressed: _busy ? null : _pickCsv,
                  ),
                ),
                if (_csvEmails.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    s.bulkInviteFilePicked(_csvEmails.length),
                    style: TextStyle(
                      fontSize: 13,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: s.bulkInviteRole,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final r in UserRole.values)
                    DropdownMenuItem(
                      value: r,
                      child: Text(roleLabel(s, r),
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _role = v);
                },
              ),
              if (_result != null) ...[
                const SizedBox(height: 16),
                _summary(context, s, tokens),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                        _result == null ? s.cancel : s.bulkInviteDone),
                  ),
                  const Spacer(),
                  FilledButton(
                    // The app theme gives every FilledButton an
                    // infinite min width (Size.fromHeight(52)), which
                    // is fine in a bounded Column but crashes this
                    // sheet: the bottom-sheet Row hands the button
                    // unbounded constraints, and an infinite min
                    // width is an invalid constraint ("BoxConstraints
                    // forces an infinite width" at this line — the
                    // blank-sheet bug). A finite minimum keeps the
                    // button content-sized here.
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                    onPressed:
                        _busy || _result != null ? null : _createInvites,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(s.bulkInviteCreate),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The batch summary: created count first, then each skip
  /// group with its reason (capped at 5 emails per group so
  /// a long list never overflows the sheet).
  Widget _summary(BuildContext context, AppStrings s, AppColors tokens) {
    final result = _result!;
    Widget skipGroup(String reason, List<String> emails) {
      if (emails.isEmpty) return const SizedBox.shrink();
      final shown = emails.take(5).toList();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${s.bulkInviteSkipped} (${emails.length}) — $reason',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.textSecondary,
              ),
            ),
            for (final email in shown)
              Text(
                email,
                style: TextStyle(fontSize: 13, color: tokens.textTertiary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (emails.length > 5)
              Text(
                '+${emails.length - 5}',
                style: TextStyle(fontSize: 13, color: tokens.textTertiary),
              ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.bulkInviteCreated(result.created.length),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          skipGroup(s.bulkInviteAlreadyMember, result.alreadyMember),
          skipGroup(s.bulkInviteAlreadyInvited, result.alreadyInvited),
          skipGroup(s.bulkInviteInvalid, _invalid),
        ],
      ),
    );
  }
}
