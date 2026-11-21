import 'package:flutter/material.dart';
import '../models/task_item.dart';
import '../theme/app_tokens.dart';

/// Dependency chains, computed in Dart from `dependsOnTaskId`
/// links. A chain is an ordered run of tasks where each step waits
/// on the one before it (Frame the shower -> Plumbing -> Install
/// the vanity -> Paint). A task with no links is standalone and
/// never appears in a chain.
class ChainIndex {
  /// taskId -> the full ordered chain it belongs to (length >= 2).
  final Map<String, List<TaskItem>> chainOf;

  /// taskId -> its 0-based position inside its chain.
  final Map<String, int> positionOf;

  /// taskId -> task, for predecessor lookups.
  final Map<String, TaskItem> byId;

  const ChainIndex(this.chainOf, this.positionOf, this.byId);

  factory ChainIndex.from(List<TaskItem> all) {
    final byId = {for (final t in all) t.id: t};
    final children = <String, List<TaskItem>>{};
    for (final t in all) {
      final dep = t.dependsOnTaskId;
      if (dep != null && byId.containsKey(dep)) {
        children.putIfAbsent(dep, () => []).add(t);
      }
    }
    int stepOrder(TaskItem a, TaskItem b) {
      final da = a.dueDate ?? DateTime(2100);
      final db = b.dueDate ?? DateTime(2100);
      final c = da.compareTo(db);
      return c != 0 ? c : a.title.compareTo(b.title);
    }

    for (final list in children.values) {
      list.sort(stepOrder);
    }
    final isChild = <String>{
      for (final list in children.values)
        for (final t in list) t.id,
    };

    final chainOf = <String, List<TaskItem>>{};
    final positionOf = <String, int>{};
    final visited = <String>{};

    void visit(TaskItem t, List<TaskItem> chain) {
      if (!visited.add(t.id)) return;
      chain.add(t);
      for (final c in children[t.id] ?? const <TaskItem>[]) {
        visit(c, chain);
      }
    }

    void register(List<TaskItem> chain) {
      if (chain.length < 2) return;
      for (var i = 0; i < chain.length; i++) {
        chainOf[chain[i].id] = chain;
        positionOf[chain[i].id] = i;
      }
    }

    // Walk each tree from its root: a task that has children but
    // is not itself a child inside this task set. Depth-first, so
    // every step lands after the step it depends on; if one step
    // unlocks two, they appear one after the other.
    final roots = all
        .where((t) => children.containsKey(t.id) && !isChild.contains(t.id))
        .toList()
      ..sort(stepOrder);
    for (final r in roots) {
      final chain = <TaskItem>[];
      visit(r, chain);
      register(chain);
    }
    // Leftovers: cycles or partial sets (e.g. a filtered list where
    // the root is not visible). Walk anything linked that the root
    // pass did not reach.
    for (final t in all) {
      if (visited.contains(t.id)) continue;
      final linked = children.containsKey(t.id) ||
          (t.dependsOnTaskId != null && byId.containsKey(t.dependsOnTaskId));
      if (!linked) continue;
      final chain = <TaskItem>[];
      visit(t, chain);
      register(chain);
    }
    return ChainIndex(chainOf, positionOf, byId);
  }

  bool isInChain(TaskItem t) => chainOf.containsKey(t.id);

  TaskItem? predecessor(TaskItem t) {
    final dep = t.dependsOnTaskId;
    return dep == null ? null : byId[dep];
  }

  bool isLockedNow(TaskItem t) => t.isLocked(predecessor(t));

  TaskItem? nextAfter(TaskItem t) {
    final chain = chainOf[t.id];
    final pos = positionOf[t.id];
    if (chain == null || pos == null || pos + 1 >= chain.length) return null;
    return chain[pos + 1];
  }
}

/// One chain step: the connecting rail + node on the left, the
/// step's card on the right. The line segment above the node is
/// green once the previous step is Done; the segment below is
/// green once this step is Done. Locked steps render dimmed.
class ChainStepRow extends StatelessWidget {
  final TaskItem task;
  final TaskItem? previous;
  final bool isFirst;
  final bool isLast;
  final bool dimmed;
  final Widget child;

  const ChainStepRow({
    super.key,
    required this.task,
    required this.previous,
    required this.isFirst,
    required this.isLast,
    required this.child,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final border = tokens.border;
    final green = tokens.statusDone;
    final topColor =
        (previous != null && previous!.status == TaskStatus.done)
            ? green
            : border;
    final bottomColor = task.status == TaskStatus.done ? green : border;
    // The segment above a soft-linked step is dashed: the order
    // is the usual one, but the step may start before the line
    // is "complete".
    final softLink = task.dependsOnTaskId != null && task.dependsSoft;
    return Opacity(
      opacity: dimmed ? 0.62 : 1,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 26,
              child: Stack(
                children: [
                  if (!isFirst)
                    Positioned(
                      left: 12,
                      top: 0,
                      height: 25,
                      child: softLink
                          ? CustomPaint(
                              painter: _VDashPainter(topColor),
                              child: const SizedBox(width: 2, height: 25),
                            )
                          : Container(width: 2, color: topColor),
                    ),
                  if (!isLast)
                    Positioned(
                      left: 12,
                      top: 25,
                      bottom: 0,
                      child: Container(width: 2, color: bottomColor),
                    ),
                  Positioned(
                    left: 1,
                    top: 13,
                    child: _ChainNode(task: task, locked: dimmed),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _ChainNode extends StatelessWidget {
  final TaskItem task;
  final bool locked;
  const _ChainNode({required this.task, required this.locked});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final Widget icon;
    final Color bg;
    BoxBorder? border;
    List<BoxShadow>? shadow;
    if (task.status == TaskStatus.done) {
      bg = tokens.statusDone;
      icon = const Icon(Icons.check, size: 13, color: Colors.white);
    } else if (locked) {
      bg = tokens.surface;
      border = Border.all(color: tokens.border);
      icon = Icon(Icons.lock_outline,
          size: 12, color: tokens.textTertiary);
    } else if (task.status == TaskStatus.blocked) {
      bg = tokens.danger;
      icon = const Icon(Icons.priority_high, size: 13, color: Colors.white);
    } else if (task.dependsOnTaskId != null && task.dependsSoft) {
      // Soft link: hollow accent ring - in the chain, but free
      // to start before the previous step is done.
      bg = tokens.surface;
      border = Border.all(color: AppTokens.accent, width: 2);
      icon = const Icon(Icons.circle, size: 7, color: AppTokens.accent);
    } else {
      // Unlocked and ready (to do / to confirm / in progress).
      bg = AppTokens.accent;
      shadow = [
        BoxShadow(
            color: AppTokens.accent.withValues(alpha: 0.18), spreadRadius: 3),
      ];
      icon = const Icon(Icons.circle, size: 8, color: Colors.white);
    }
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: border,
        boxShadow: shadow,
      ),
      child: Center(child: icon),
    );
  }
}

/// Small pill shown on a locked step: a lock + "Waiting on: X".
class WaitingChip extends StatelessWidget {
  final String label;
  const WaitingChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline,
              size: 12, color: tokens.textTertiary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: tokens.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// Small pill shown on a soft-linked step: a link icon +
/// "Usually after: X - can start early".
class SoftLinkChip extends StatelessWidget {
  final String label;
  const SoftLinkChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTokens.accent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link, size: 12, color: tokens.accentText),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: tokens.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// Miniature chain for the task detail screen and board cards:
/// one small node per step, joined by a line that turns green as
/// steps complete. [currentId] gets the accent ring.
class ChainStrip extends StatelessWidget {
  final ChainIndex index;
  final List<TaskItem> chain;
  final String currentId;

  const ChainStrip({
    super.key,
    required this.index,
    required this.chain,
    required this.currentId,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final border = tokens.border;
    final green = tokens.statusDone;
    return Row(
      children: [
        for (var i = 0; i < chain.length; i++) ...[
          if (i > 0)
            Expanded(
              child: chain[i].dependsSoft &&
                      chain[i].dependsOnTaskId != null &&
                      chain[i - 1].status != TaskStatus.done
                  ? CustomPaint(
                      painter: _HDashPainter(border),
                      child: const SizedBox(height: 2),
                    )
                  : Container(
                      height: 2,
                      color: chain[i - 1].status == TaskStatus.done
                          ? green
                          : border,
                    ),
            ),
          _StripDot(
            task: chain[i],
            isCurrent: chain[i].id == currentId,
            locked: index.isLockedNow(chain[i]),
          ),
        ],
      ],
    );
  }
}

class _StripDot extends StatelessWidget {
  final TaskItem task;
  final bool isCurrent;
  final bool locked;
  const _StripDot(
      {required this.task, required this.isCurrent, required this.locked});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final Widget icon;
    final Color bg;
    BoxBorder? border;
    List<BoxShadow>? shadow;
    if (task.status == TaskStatus.done) {
      bg = tokens.statusDone;
      icon = const Icon(Icons.check, size: 10, color: Colors.white);
    } else if (locked) {
      bg = tokens.surface;
      border = Border.all(color: tokens.border);
      icon = Icon(Icons.lock_outline,
          size: 9, color: tokens.textTertiary);
    } else if (task.dependsOnTaskId != null && task.dependsSoft) {
      bg = tokens.surface;
      border = Border.all(color: AppTokens.accent, width: 1.5);
      icon = const Icon(Icons.circle, size: 5, color: AppTokens.accent);
    } else {
      bg = AppTokens.accent;
      icon = const Icon(Icons.circle, size: 6, color: Colors.white);
    }
    if (isCurrent && task.status != TaskStatus.done) {
      shadow = [
        BoxShadow(
            color: AppTokens.accent.withValues(alpha: 0.18), spreadRadius: 3),
      ];
    }
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: border,
        boxShadow: shadow,
      ),
      child: Center(child: icon),
    );
  }
}

/// Vertical dashed line (soft-link segment in the chain rail).
class _VDashPainter extends CustomPainter {
  final Color color;
  const _VDashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dash = 4.0;
    const gap = 3.0;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(Offset(1, y), Offset(1, y + dash), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _VDashPainter old) => old.color != color;
}

/// Horizontal dashed line (soft-link connector in the strip).
class _HDashPainter extends CustomPainter {
  final Color color;
  const _HDashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dash = 4.0;
    const gap = 3.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 1), Offset(x + dash, 1), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _HDashPainter old) => old.color != color;
}
