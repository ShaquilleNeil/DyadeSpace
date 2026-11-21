import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../providers/locale_provider.dart';
import 'member_tile.dart';
import 'section_label.dart';

/// Multi-select assignment picker: search box + pills only, no
/// checklist. The crew is never listed up front:
/// - top row: the "Assigned to" heading with a search box right
///   next to it, inline on the same row;
/// - directly below: everyone already selected, each as a pill
///   with an X — tapping the X removes that person;
/// - while the user is typing, matching names appear in a small
///   dropdown menu anchored directly beneath the search box. The
///   menu is a floating overlay (Flutter's built-in Autocomplete
///   options view, anchored to the field with a follower), so it
///   sits on top of the form content instead of pushing it down.
///   Tapping a name adds that person as a pill, clears the query
///   and closes the menu. Tapping outside the menu or leaving
///   the search box closes it. People already selected are not
///   offered again — the pill's X is how they are removed. Empty
///   query = no menu; no match = no menu. Results are filtered
///   live by name (case-insensitive).
/// Used by the task editor on phone and web (the web board opens
/// the same TaskScreen). Removing everyone leaves the task
/// unassigned — the caller stores an empty list, which the task
/// card and detail screen render as Unassigned.
class AssigneePicker extends ConsumerStatefulWidget {
  final List<AppUser> users;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  const AssigneePicker({
    super.key,
    required this.users,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  ConsumerState<AssigneePicker> createState() => _AssigneePickerState();
}

class _AssigneePickerState extends ConsumerState<AssigneePicker> {
  final _search = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _add(String id) {
    if (widget.selectedIds.contains(id)) return;
    widget.onChanged({...widget.selectedIds, id});
    // Clear the query so the dropdown closes and the box is
    // ready for the next name.
    _search.clear();
  }

  void _remove(String id) {
    final next = Set<String>.of(widget.selectedIds)..remove(id);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final selectedUsers =
        widget.users.where((u) => widget.selectedIds.contains(u.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Heading + search box on one row.
        Row(
          children: [
            SectionLabel(s.assignee),
            const SizedBox(width: 10),
            Expanded(
              child: Autocomplete<AppUser>(
                textEditingController: _search,
                focusNode: _focusNode,
                optionsBuilder: (value) {
                  final query = value.text.trim().toLowerCase();
                  if (query.isEmpty) {
                    return const Iterable<AppUser>.empty();
                  }
                  return widget.users.where((u) =>
                      !widget.selectedIds.contains(u.id) &&
                      u.name.toLowerCase().contains(query));
                },
                displayStringForOption: (u) => u.name,
                onSelected: (u) => _add(u.id),
                optionsViewBuilder: (context, onSelected, options) {
                  final colorScheme = Theme.of(context).colorScheme;
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      color: colorScheme.surface,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: ListView(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          children: [
                            for (final u in options)
                              ListTile(
                                key: ValueKey('assignee-${u.id}'),
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                title: Text(
                                  '${u.name} · ${roleLabel(s, u.role)}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.add, size: 20),
                                onTap: () => onSelected(u),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 18),
                      hintText: s.searchPeopleHint,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Selected people as pills with an X; "Unassigned" when none.
        if (selectedUsers.isEmpty)
          Text(
            s.unassigned,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final u in selectedUsers)
                InputChip(
                  key: ValueKey('assignee-pill-${u.id}'),
                  label: Text(u.name),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () => _remove(u.id),
                ),
            ],
          ),
      ],
    );
  }
}
