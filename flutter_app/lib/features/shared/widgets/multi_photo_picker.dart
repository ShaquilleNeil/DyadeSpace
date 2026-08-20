import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_spacing.dart';

/// Grid of picked photo thumbnails (each removable) plus an "add photo"
/// tile — factored out of the task-completion sheet so material requests
/// and daily reports can attach photos the same way.
class MultiPhotoPicker extends StatelessWidget {
  const MultiPhotoPicker({
    super.key,
    required this.photos,
    required this.onAdd,
    required this.onRemoveAt,
  });

  final List<File> photos;
  final ValueChanged<List<File>> onAdd;
  final ValueChanged<int> onRemoveAt;

  Future<void> _pickPhotos() async {
    final picked = await ImagePicker().pickMultiImage(maxWidth: 1600, imageQuality: 70);
    if (picked.isNotEmpty) {
      onAdd(picked.map((x) => File(x.path)).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (var i = 0; i < photos.length; i++)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
            child: Stack(
              children: [
                Image.file(photos[i], width: 80, height: 80, fit: BoxFit.cover),
                Positioned(
                  right: 0,
                  top: 0,
                  child: InkWell(
                    onTap: () => onRemoveAt(i),
                    child: const CircleAvatar(
                      radius: 10,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        InkWell(
          onTap: _pickPhotos,
          borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
            ),
            child: const Icon(Icons.add_a_photo),
          ),
        ),
      ],
    );
  }
}
