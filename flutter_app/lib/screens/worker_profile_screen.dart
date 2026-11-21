import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../l10n/app_strings.dart';
import '../models/app_user.dart';
import '../models/site.dart';
import '../models/task_item.dart';
import '../models/time_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/sites_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/time_entries_provider.dart';
import '../services/profile_photo_service.dart';
import '../services/task_service.dart';
import '../theme/app_tokens.dart';
import '../utils/hours_format.dart';
import '../widgets/empty_state.dart';
import '../widgets/hours_entry_editor.dart';
import '../widgets/member_tile.dart';
import '../widgets/site_visits_list.dart';
import '../widgets/task_card.dart';
import '../widgets/week_hours_header.dart';
import 'clock_location_screen.dart';
import 'task_screen.dart';

/// One worker's profile: photo, name, role, email, current
/// clock-in status (where + since, or not clocked in), and two
/// tabs below it — Tasks (their open tasks, the same list as
/// their section on the By person screen) and Clock-in (their
/// clock-in/out history — each entry opens its location on the
/// map). A user viewing their OWN profile can set their
/// profile photo here (camera or gallery); anyone else's
/// profile is view-only. An admin viewing SOMEONE ELSE's
/// profile also gets a role dropdown — never on their own
/// profile, so an admin cannot demote themselves from here.
/// An admin or manager viewing the profile also gets an edit
/// button on each history row (same audience as the Hours
/// screen). `initialTabIndex` opens the screen on a tab other
/// than Tasks — the Hours screen uses it to land straight on
/// the Clock-in tab.
class WorkerProfileScreen extends ConsumerStatefulWidget {
  final AppUser user;

  /// 0 = Tasks, 1 = Clock-in. Defaults to Tasks.
  final int initialTabIndex;

  const WorkerProfileScreen({
    super.key,
    required this.user,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<WorkerProfileScreen> createState() =>
      _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends ConsumerState<WorkerProfileScreen> {
  // No eager ProfilePhotoService field: its constructor reads
  // FirebaseStorage.instance, which must not happen until the
  // user actually picks a photo (and must not happen at all in
  // tests / before Firebase is ready). The service is created
  // inside _changePhoto instead.
  String? _photoUrl;
  bool _uploading = false;

  /// The role shown on this screen. Local state (not
  /// widget.user.role) so an admin's change reflects at once;
  /// the users list refreshes from Firestore separately.
  late UserRole _role;
  bool _changingRole = false;

  @override
  void initState() {
    super.initState();
    _photoUrl = widget.user.photoUrl;
    _role = widget.user.role;
  }

  String _timeOf(DateTime at) => DateFormat('HH:mm').format(at);

  Future<void> _changePhoto(AppStrings s) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(s.takePhoto),
              onTap: () => Navigator.of(sheetContext).pop(
                ImageSource.camera,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(s.choosePhoto),
              onTap: () => Navigator.of(sheetContext).pop(
                ImageSource.gallery,
              ),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final file = await ProfilePhotoService().pickPhoto(source);
    if (file == null) return;
    setState(() => _uploading = true);
    // Unique path per upload (see ProfilePhotoService): the old
    // URL stays valid until the doc write below succeeds, so a
    // failed write can never leave a dead avatar URL on the doc.
    final previousUrl = _photoUrl;
    String? uploadedUrl;
    try {
      final service = ProfilePhotoService();
      uploadedUrl = await service.uploadPhoto(
        uid: widget.user.id,
        file: file,
      );
      await ref.read(authServiceProvider).updatePhotoUrl(
            uid: widget.user.id,
            photoUrl: uploadedUrl,
          );
      if (!mounted) return;
      setState(() => _photoUrl = uploadedUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.photoUpdated)),
      );
      // Only now, with the new URL saved on the doc, is the old
      // file deleted — best-effort, never surfacing as a failure.
      if (previousUrl != null && previousUrl != uploadedUrl) {
        await service.deletePhotoByUrl(previousUrl);
      }
    } catch (_) {
      // The upload succeeded but the doc write failed: remove
      // the orphaned new file so it does not linger in Storage
      // (best-effort — the doc still points at the old, valid
      // URL either way).
      if (uploadedUrl != null) {
        await ProfilePhotoService().deletePhotoByUrl(uploadedUrl);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.profilePhotoUploadFailed)),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Admin-only role change (the caller guards that this is
  /// someone else's profile). The dropdown updates at once;
  /// on failure the old role comes back and the error is shown.
  Future<void> _changeRole(AppStrings s, UserRole newRole) async {
    final previous = _role;
    setState(() {
      _role = newRole;
      _changingRole = true;
    });
    try {
      await ref.read(authServiceProvider).updateRole(
            uid: widget.user.id,
            role: newRole,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.roleUpdated)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _role = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.roleUpdateFailed)),
      );
    } finally {
      if (mounted) setState(() => _changingRole = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final isOwnProfile = me != null && me.id == widget.user.id;
    final openAsync = ref.watch(openEntryForUserProvider(widget.user.id));
    final historyAsync = ref.watch(entriesForUserProvider(widget.user.id));
    final allTasks = ref.watch(allTasksProvider).valueOrNull ?? [];
    final siteById = ref.watch(siteByIdProvider);
    final myTasks = TaskService.tasksForPerson(allTasks, widget.user.id);
    // The Hours screen's audience: only an admin or a manager
    // may correct an entry from the history list.
    final canEdit = me != null &&
        (me.role == UserRole.admin || me.role == UserRole.manager);

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.user.name),
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        borderRadius:
                            BorderRadius.circular(AppTokens.cardRadius),
                        border: Border.all(color: tokens.border),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left: photo, with the role picker right
                          // below it (admin viewing someone else) or
                          // the photo button (own profile).
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              RoleAvatar(
                                name: widget.user.name,
                                role: widget.user.role,
                                size: 64,
                                photoUrl: _photoUrl,
                              ),
                              // Admin-only, never on your own profile:
                              // an admin must not be able to demote
                              // themselves from here. `value:` + a key
                              // on _role: the items are the fixed
                              // UserRole enum, so _role is always one
                              // of them; the key rebuilds the field
                              // fresh after a change.
                              if (me != null &&
                                  me.role == UserRole.admin &&
                                  !isOwnProfile) ...[
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    DropdownButton<UserRole>(
                                      key: ValueKey(_role),
                                      value: _role,
                                      isDense: true,
                                      underline: const SizedBox.shrink(),
                                      iconSize: 18,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: tokens.textPrimary,
                                      ),
                                      items: [
                                        for (final r in UserRole.values)
                                          DropdownMenuItem(
                                            value: r,
                                            child: Text(roleLabel(s, r)),
                                          ),
                                      ],
                                      onChanged: _changingRole
                                          ? null
                                          : (v) {
                                              if (v != null && v != _role) {
                                                _changeRole(s, v);
                                              }
                                            },
                                    ),
                                    if (_changingRole) ...[
                                      const SizedBox(width: 6),
                                      const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                              if (isOwnProfile) ...[
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  icon: _uploading
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.photo_camera_outlined,
                                          size: 16,
                                        ),
                                  label: Text(
                                    _photoUrl == null
                                        ? s.addProfilePhoto
                                        : s.changeProfilePhoto,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(0, 28),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                  ),
                                  onPressed:
                                      _uploading ? null : () => _changePhoto(s),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.user.name,
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    roleLabel(s, _role).toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: tokens.textTertiary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.user.email,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: tokens.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    openAsync.when(
                      loading: () => const SizedBox(
                        height: 56,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => Text(
                        'Error: $e',
                        style: TextStyle(color: tokens.textSecondary),
                      ),
                      data: (open) {
                        if (open == null) {
                          return Container(
                            decoration: BoxDecoration(
                              color: tokens.surface,
                              borderRadius:
                                  BorderRadius.circular(AppTokens.cardRadius),
                              border: Border.all(color: tokens.border),
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: tokens.statusTodo,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    s.notClockedIn,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ClockLocationScreen(entry: open),
                              ),
                            );
                          },
                          borderRadius:
                              BorderRadius.circular(AppTokens.cardRadius),
                          child: Container(
                            decoration: BoxDecoration(
                              color: tokens.surface,
                              borderRadius:
                                  BorderRadius.circular(AppTokens.cardRadius),
                              border: Border.all(color: tokens.border),
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: tokens.statusDone,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        open.siteName.isEmpty
                                            ? s.clockedIn
                                            : s.clockedInAt(open.siteName),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${s.clockedInSince(_timeOf(open.clockInAt))} · ${formatHoursMinutes(open.hoursSoFar)}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: tokens.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    size: 20, color: tokens.textTertiary),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedTabBarDelegate(
                TabBar(
                  tabs: [
                    Tab(text: s.tasks),
                    Tab(text: s.clockIn),
                  ],
                ),
                tokens.background,
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _tasksTab(context, s, siteById, myTasks),
              _historyTab(context, s, tokens, historyAsync, canEdit),
            ],
          ),
        ),
      ),
    );
  }

  /// Tasks tab: the person's open tasks, the same list as their
  /// section on the By person screen (TaskService.tasksForPerson),
  /// each opening the task screen. EmptyState when none.
  Widget _tasksTab(
    BuildContext context,
    AppStrings s,
    Map<String, Site> siteById,
    List<TaskItem> tasks,
  ) {
    if (tasks.isEmpty) {
      return ListView(
        key: const PageStorageKey('profile-tasks'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          EmptyState(
            icon: Icons.inbox_outlined,
            title: s.noTasks,
          ),
        ],
      );
    }
    return ListView.builder(
      key: const PageStorageKey('profile-tasks'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final t = tasks[index];
        return TaskCard(
          task: t,
          site: siteById[t.siteId],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TaskScreen(task: t)),
          ),
        );
      },
    );
  }

  /// Clock-in tab: the week-hours header first ("This week:
  /// X h Y min"), then the history list — each entry with the
  /// day's site visits underneath it. Admin/manager viewers
  /// get an edit button on each row (same dialog as the
  /// Hours screen); workers never see it on anyone's
  /// profile, since the rules would refuse their edit.
  Widget _historyTab(
    BuildContext context,
    AppStrings s,
    AppColors tokens,
    AsyncValue<List<TimeEntry>> historyAsync,
    bool canEdit,
  ) {
    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ListView(
        key: const PageStorageKey('profile-history'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Text(
            'Error: $e',
            style: TextStyle(color: tokens.textSecondary),
          ),
        ],
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return ListView(
            key: const PageStorageKey('profile-history'),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Text(
                s.profileNoHistory,
                style: TextStyle(color: tokens.textSecondary),
              ),
            ],
          );
        }
        return ListView.builder(
          key: const PageStorageKey('profile-history'),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          itemCount: entries.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: WeekHoursHeader(entries: entries, strings: s),
              );
            }
            final e = entries[index - 1];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _historyTile(context, s, tokens, e, canEdit),
                _EntryVisits(entry: e, strings: s),
              ],
            );
          },
        );
      },
    );
  }

  Widget _historyTile(
    BuildContext context,
    AppStrings s,
    AppColors tokens,
    TimeEntry e,
    bool canEdit,
  ) {
    final flagged = e.flagged;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${DateFormat('EEE MMM d').format(e.clockInAt)} · ${e.siteName.isEmpty ? s.noSite : e.siteName}',
                // Two lines: at phone width the date + site +
                // badge don't fit on one, and the site name was
                // cut off ("Boucher…"). The badge stays on the
                // first line.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (e.auto)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  s.autoTag,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: tokens.accentText,
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (flagged ? tokens.statusBlocked : tokens.statusDone)
                    .withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                // Just "Flagged": the full "Flagged: <reason>"
                // pill is so wide the date + site no longer fit
                // even on two lines. The reason still shows on
                // the map screen when the entry is tapped.
                flagged ? s.hoursFlagged : s.hoursVerified,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: flagged ? tokens.statusBlocked : tokens.statusDone,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          e.clockOutAt == null
              ? '${_timeOf(e.clockInAt)} – ${s.hoursStillClockedIn}'
              : '${_timeOf(e.clockInAt)} – ${_timeOf(e.clockOutAt!)} · ${formatHoursMinutes(e.hours ?? e.hoursSoFar)}',
          style: TextStyle(color: tokens.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: s.hoursEditEntry,
                // The button handles its own tap, so it does
                // not open the map (same pattern as the old
                // Hours entry tiles).
                onPressed: () => showEditTimeEntry(context, ref, e),
              ),
            Icon(Icons.chevron_right, size: 20, color: tokens.textTertiary),
          ],
        ),
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ClockLocationScreen(entry: e),
            ),
          );
        },
      ),
    );
  }
}

/// One entry's site visits, under its history tile: the
/// day's moves (site, arrived, left, duration), with the
/// open visit marked "Here now". Nothing renders when the
/// entry has no visits — a day the worker never stayed
/// anywhere long enough to count, or an entry from before
/// visit logging existed.
class _EntryVisits extends ConsumerWidget {
  final TimeEntry entry;
  final AppStrings strings;

  const _EntryVisits({required this.entry, required this.strings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitsAsync = ref.watch(visitsForEntryProvider(entry.id));
    final visits = visitsAsync.valueOrNull ?? [];
    if (visits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SiteVisitsList(
        visits: visits,
        entryClockOutAt: entry.clockOutAt,
        strings: strings,
      ),
    );
  }
}

/// Keeps the profile's TabBar pinned at the top while the
/// header scrolls away (NestedScrollView header). The bar gets
/// an opaque background so tab content never shows through it.
class _PinnedTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color background;

  const _PinnedTabBarDelegate(this.tabBar, this.background);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      Container(color: background, child: tabBar);

  @override
  bool shouldRebuild(_PinnedTabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar || oldDelegate.background != background;
}
