import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/client_share.dart';
import '../models/site.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../services/client_share_service.dart';
import '../theme/app_tokens.dart';

/// The "Share with client" dialog (web Sites screen): shows
/// the site's live client link if one exists, creates one if
/// it does not, and offers Copy / New link (revokes the old
/// one) / Revoke. Creating a link revokes any previous link
/// for the site first, so there is exactly one live link per
/// site. The link itself is just a URL — the client opens it
/// with no app or login.
Future<void> showClientShareDialog(
  BuildContext context,
  WidgetRef ref,
  Site site,
) async {
  final me = ref.read(currentUserProvider).valueOrNull;
  if (me == null) return;
  final service = ref.read(clientShareServiceProvider);
  ClientShare? share;
  try {
    final existing = await service
        .watchSharesForSite(site.id)
        .first;
    share = existing.firstOrNull;
  } catch (_) {
    share = null;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => _ClientShareDialog(
      site: site,
      initialShare: share,
    ),
  );
}

class _ClientShareDialog extends ConsumerStatefulWidget {
  final Site site;
  final ClientShare? initialShare;
  const _ClientShareDialog({required this.site, this.initialShare});

  @override
  ConsumerState<_ClientShareDialog> createState() =>
      _ClientShareDialogState();
}

class _ClientShareDialogState extends ConsumerState<_ClientShareDialog> {
  ClientShare? _share;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _share = widget.initialShare;
  }

  Future<void> _create() async {
    final s = ref.read(stringsProvider);
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null || _busy) return;
    setState(() => _busy = true);
    try {
      final share = await ref.read(clientShareServiceProvider).createShare(
            site: widget.site,
            createdBy: me.id,
          );
      if (!mounted) return;
      setState(() {
        _share = share;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.clientShareLinkCreated)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.clientShareLoadFailed)),
      );
    }
  }

  Future<void> _revoke() async {
    final s = ref.read(stringsProvider);
    final share = _share;
    if (share == null || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(clientShareServiceProvider).revokeShare(share.token);
      if (!mounted) return;
      setState(() {
        _share = null;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.clientShareLinkRevoked)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _regenerate() async {
    final s = ref.read(stringsProvider);
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null || _busy) return;
    setState(() => _busy = true);
    try {
      final share =
          await ref.read(clientShareServiceProvider).regenerateShare(
                site: widget.site,
                createdBy: me.id,
              );
      if (!mounted) return;
      setState(() {
        _share = share;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.clientShareLinkRegenerated)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final tokens = AppTokens.of(context);
    final share = _share;
    final url = share == null ? null : clientShareUrl(share.token);
    return AlertDialog(
      title: Text(s.clientShareTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.site.name} — ${s.clientShareIntro}',
              style: TextStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: 16),
            if (url == null)
              Text(s.clientShareNoLinkYet,
                  style: TextStyle(color: tokens.textSecondary))
            else
              SelectableText(
                url,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(s.close),
        ),
        if (share != null) ...[
          TextButton(
            onPressed: _busy ? null : _revoke,
            child: Text(s.clientShareRevoke,
                style: TextStyle(color: tokens.danger)),
          ),
          TextButton.icon(
            icon: const Icon(Icons.refresh_outlined, size: 18),
            label: Text(s.clientShareRegenerate),
            onPressed: _busy ? null : _regenerate,
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: Text(s.clientShareCopyLink),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url!));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(s.clientShareLinkCopied)),
                );
              }
            },
          ),
        ] else
          FilledButton.icon(
            icon: const Icon(Icons.link_outlined, size: 18),
            label: Text(s.shareWithClient),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
            ),
            onPressed: _busy ? null : _create,
          ),
      ],
    );
  }
}
