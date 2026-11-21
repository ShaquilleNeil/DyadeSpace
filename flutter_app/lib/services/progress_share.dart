import 'package:intl/intl.dart';
import '../l10n/app_strings.dart';
import '../models/site.dart';
import '../models/task_item.dart';
import '../widgets/status_indicator.dart';

/// Builds the client-facing progress text for one site, in the
/// current app language: done / in progress / to confirm /
/// paused / to do / blocked (with its reason) sections, each
/// omitted when empty. Every status is listed — the old text
/// silently dropped to-confirm, paused and to-do tasks, so a
/// site with only those looked like no work at all. Shared by
/// the phone Reports screen and the web control center's
/// Reports section so the shared update reads the same
/// everywhere.
String buildProgressText(AppStrings s, Site site, List<TaskItem> all) {
  final tasks = all.where((t) => t.siteId == site.id).toList();
  final date = DateFormat('MMM d, yyyy').format(DateTime.now());
  final buf =
      StringBuffer('${site.name} \u2014 ${s.progressUpdate} \u2014 $date');
  var reported = 0;
  void section(String label, TaskStatus status, {bool blocked = false}) {
    final items = tasks.where((t) => t.status == status).toList();
    if (items.isEmpty) return;
    reported += items.length;
    buf.write('\n\n$label:');
    for (final t in items) {
      final unit = t.unit.isEmpty ? '' : ' (${t.unit})';
      final reason =
          blocked ? ' - ${blockedReasonLabel(s, t.blockedReason)}' : '';
      buf.write('\n- ${t.title}$unit$reason');
    }
  }

  section(s.done, TaskStatus.done);
  section(s.inProgress, TaskStatus.inProgress);
  section(s.toConfirm, TaskStatus.toConfirm);
  section(s.paused, TaskStatus.paused);
  section(s.toDo, TaskStatus.todo);
  section(s.blocked, TaskStatus.blocked, blocked: true);
  if (reported == 0) {
    buf.write('\n\n${s.noWorkYet}');
  }
  return buf.toString();
}
