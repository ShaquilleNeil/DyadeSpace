import 'package:flutter/material.dart';

import '../../../theme/app_spacing.dart';

/// Shared search bar used across staff/project/employee list screens —
/// previously copy-pasted with slightly different padding in each place.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onChanged, this.hintText = 'Search'});

  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search),
        ),
      ),
    );
  }
}
