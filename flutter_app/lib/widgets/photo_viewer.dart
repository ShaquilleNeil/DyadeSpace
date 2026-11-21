import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../providers/locale_provider.dart';
import '../theme/app_tokens.dart';
import '../utils/gallery_save.dart';

/// One photo in the viewer: a network URL, a local file path,
/// or both (the local file wins while it exists — pending
/// uploads that have no URL yet). [label] is the caption shown
/// under the counter (task title, stop address, …).
class PhotoViewerItem {
  final String? url;
  final String? localPath;
  final String? label;

  const PhotoViewerItem({this.url, this.localPath, this.label});
}

/// Opens the full-screen viewer on [initialIndex], swipeable
/// across the whole [items] set. Used everywhere a photo is
/// shown: task proof, run stops, EOD report strip, material
/// requests, and chat images.
void showPhotoViewer(
  BuildContext context, {
  required List<PhotoViewerItem> items,
  required int initialIndex,
}) {
  if (items.isEmpty) return;
  final start = initialIndex.clamp(0, items.length - 1);
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _PhotoViewerPage(items: items, initialIndex: start),
    ),
  );
}

class _PhotoViewerPage extends ConsumerStatefulWidget {
  final List<PhotoViewerItem> items;
  final int initialIndex;

  const _PhotoViewerPage({required this.items, required this.initialIndex});

  @override
  ConsumerState<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends ConsumerState<_PhotoViewerPage> {
  late final PageController _pageController;
  late int _index;
  bool _busy = false;

  /// Network photos already fetched this session, so a second
  /// Download/Share tap reuses the bytes.
  final Map<int, Uint8List> _downloaded = {};

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// The image bytes for [index]: the item's own file when it
  /// exists (read through XFile, so blob URLs work on web too),
  /// otherwise the network photo fetched over HTTP. Cached per
  /// index for the session. Null when the photo cannot be
  /// fetched. Bytes — never File: dart:io cannot compile for web.
  Future<Uint8List?> _imageBytes(int index) async {
    final cached = _downloaded[index];
    if (cached != null) return cached;
    final item = widget.items[index];
    Uint8List? bytes;
    if (item.localPath != null) {
      try {
        bytes = await XFile(item.localPath!).readAsBytes();
      } catch (_) {
        bytes = null;
      }
    }
    final url = item.url;
    if (bytes == null && url != null) {
      try {
        final data = await NetworkAssetBundle(Uri.parse(url)).load(url);
        bytes = data.buffer.asUint8List();
      } catch (_) {
        bytes = null;
      }
    }
    if (bytes != null) _downloaded[index] = bytes;
    return bytes;
  }

  Future<void> _download(AppStrings s) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Web has no gallery: open the original in a new tab and
      // let the browser save it. Phones save the bytes to the
      // gallery (same result as before, via bytes now).
      final item = widget.items[_index];
      if (kIsWeb) {
        final url = item.url;
        if (url == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.photoSaveFailed)),
            );
          }
          return;
        }
        final ok = await launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication);
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.photoSaveFailed)),
          );
        }
        return;
      }
      final bytes = await _imageBytes(_index);
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.photoSaveFailed)),
          );
        }
        return;
      }
      final saved = await saveImageToGallery(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved ? s.photoSaved : s.photoSaveFailed)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.photoSaveFailed)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(AppStrings s) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _imageBytes(_index);
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.couldNotShare)),
          );
        }
        return;
      }
      await SharePlus.instance.share(
        ShareParams(files: [
          XFile.fromData(bytes,
              name: 'dyadespace-photo.jpg', mimeType: 'image/jpeg'),
        ]),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.couldNotShare)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final item = widget.items[_index];
    final label = item.label;
    final counter = widget.items.length > 1
        ? '${_index + 1} / ${widget.items.length}'
        : null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null && label.isNotEmpty)
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
            if (counter != null)
              Text(
                counter,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: s.download,
              onPressed: () => _download(s),
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: s.share,
              onPressed: () => _share(s),
            ),
          ],
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.items.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final it = widget.items[i];
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(child: _photoWidget(it, tokens)),
          );
        },
      ),
    );
  }

  Widget _photoWidget(PhotoViewerItem item, AppColors tokens) {
    // A local file renders from its bytes (XFile reads blob
    // URLs on web too); when the file is gone, fall through to
    // the network photo like before.
    if (item.localPath != null) {
      return FutureBuilder<Uint8List>(
        future: XFile(item.localPath!).readAsBytes(),
        builder: (context, snap) {
          if (snap.hasData) {
            return Image.memory(snap.data!, fit: BoxFit.contain);
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          return _networkPhoto(item, tokens);
        },
      );
    }
    return _networkPhoto(item, tokens);
  }

  Widget _networkPhoto(PhotoViewerItem item, AppColors tokens) {
    if (item.url == null) {
      return Icon(Icons.broken_image_outlined,
          size: 48, color: tokens.textTertiary);
    }
    return Image.network(
      item.url!,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      },
      errorBuilder: (_, __, ___) => const Icon(
        Icons.broken_image_outlined,
        size: 48,
        color: Colors.white70,
      ),
    );
  }
}
