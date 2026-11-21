import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../models/material_request.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/material_requests_provider.dart';
import '../providers/tasks_provider.dart';
import 'photo_viewer.dart';

/// "Request materials" bottom sheet, shared by the task screen
/// (taskId set) and the site screen (taskId null). The worker
/// names the item, how many, when it's needed, an optional note
/// and an optional photo; the request lands with the managers
/// as `requested`. The request id is generated up front so the
/// optional photo can be uploaded into requestPhotos/<id>
/// before the doc exists.
///
/// Returns true when the request was sent, null when the sheet
/// was dismissed without sending. The caller shows the
/// confirmation snackbar after the sheet closes — the sheet
/// never touches a context after its own pop, and the keyboard
/// is dismissed before the write.
///
/// The sheet's TextEditingControllers are owned by
/// [_MaterialRequestSheetState] and disposed in its dispose:
/// the dialog reads them before popping, never after, so the
/// old "used after being disposed" crash (a field rebuilding
/// against a controller disposed right after the pop) cannot
/// happen here.
Future<bool?> showMaterialRequestSheet(
  BuildContext context,
  WidgetRef ref, {
  required String siteId,
  String? taskId,
}) async {
  final me = ref.read(currentUserProvider).valueOrNull;
  if (me == null) return null;
  // One id for the whole sheet: the photo folder is named after
  // it, and the doc itself is created under it on submit.
  final requestId =
      FirebaseFirestore.instance.collection('materialRequests').doc().id;

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => _MaterialRequestSheet(
      siteId: siteId,
      taskId: taskId,
      requestId: requestId,
      requester: me,
    ),
  );
}

class _MaterialRequestSheet extends ConsumerStatefulWidget {
  final String siteId;
  final String? taskId;
  final String requestId;
  final AppUser requester;

  const _MaterialRequestSheet({
    required this.siteId,
    this.taskId,
    required this.requestId,
    required this.requester,
  });

  @override
  ConsumerState<_MaterialRequestSheet> createState() =>
      _MaterialRequestSheetState();
}

class _MaterialRequestSheetState
    extends ConsumerState<_MaterialRequestSheet> {
  final _itemCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _noteCtrl = TextEditingController();
  DateTime? _neededBy;
  String? _photoUrl;
  var _saving = false;

  @override
  void dispose() {
    _itemCtrl.dispose();
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = ref.read(stringsProvider);
    final item = _itemCtrl.text.trim();
    final qty = int.tryParse(_qtyCtrl.text.trim());
    if (item.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestNeedsItem)),
      );
      return;
    }
    if (qty == null || qty < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestNeedsQty)),
      );
      return;
    }
    // Dismiss the keyboard before the write: the sheet's
    // layout depends on MediaQuery viewInsets, and popping
    // while the keyboard is still animating down races the
    // inset notification against the sheet's unmount (that
    // race red-screened the app on Send). The write below
    // takes a network round-trip, so by the time we pop
    // the insets are settled.
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final url = _photoUrl;
    try {
      await ref.read(materialRequestServiceProvider).createRequestWithId(
            MaterialRequest(
              id: widget.requestId,
              requesterId: widget.requester.id,
              requesterName: widget.requester.name,
              siteId: widget.siteId,
              taskId: widget.taskId,
              item: item,
              quantity: qty,
              neededBy: _neededBy,
              note: _noteCtrl.text.trim(),
              photoUrl: url,
              status: MaterialRequestStatus.requested,
              createdAt: DateTime.now(),
            ),
          );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.materialRequestFailed('$e'))),
        );
      }
      return;
    }
    // Pop with the sheet's own context (the right route),
    // and nothing after it: the confirmation snackbar is
    // the caller's job, shown once this sheet is gone.
    // Showing it from here, across the pop, used a context
    // whose element was mid-unmount.
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _addPhoto() async {
    final s = ref.read(stringsProvider);
    // Upload straight away into the request's folder; if it
    // fails the request can still be sent without a photo.
    try {
      final url = await ref
          .read(photoServiceProvider)
          .takePhotoAndUpload('requestPhotos', widget.requestId);
      if (url != null && mounted) {
        setState(() => _photoUrl = url);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.photoUploadFailed)),
        );
      }
    }
  }

  Future<void> _pickNeededBy() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _neededBy ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _neededBy = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        // Scrollable so the keyboard can never overflow the
        // sheet on a small phone: the fields shrink away
        // under the keyboard instead of red-screening.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.requestMaterials,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 14),
              TextField(
                controller: _itemCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: s.materialItem,
                  hintText: s.materialItemHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: s.materialQuantity,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.materialNeededBy),
                      subtitle: Text(_neededBy == null
                          ? s.materialNoDate
                          : DateFormat('EEE MMM d').format(_neededBy!)),
                      trailing: IconButton(
                        icon: const Icon(Icons.calendar_month_outlined),
                        onPressed: _pickNeededBy,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: s.materialNoteOptional,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(s.addPhoto),
                    onPressed: _saving ? null : _addPhoto,
                  ),
                  if (_photoUrl != null) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => showPhotoViewer(
                        context,
                        items: [
                          PhotoViewerItem(
                            url: _photoUrl,
                            label: _itemCtrl.text.trim(),
                          ),
                        ],
                        initialIndex: 0,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(_photoUrl!,
                            width: 44, height: 44, fit: BoxFit.cover),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(s.cancel),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                    onPressed: _saving ? null : _submit,
                    child: Text(s.send),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
