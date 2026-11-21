import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_strings.dart';
import '../../models/task_item.dart';
import '../../theme/app_tokens.dart';
import '../../utils/hours_format.dart';

/// Shared building blocks for the web control center, plus the
/// section enum the shell and every view use to navigate.
///
/// RESPONSIVE RULES (the owner's brief: the site must be usable
/// on a phone, not just a desktop):
/// - width >= 900: full sidebar (232px), 4-col stat grid.
/// - 700..900: icon rail (68px), stat grid 2-col below 1000px.
/// - width < 700: sidebar becomes a drawer behind a hamburger,
///   stat cards stack 2-col then 1-col below 560px, tables
///   become stacked cards, the topbar search hides, and nothing
///   overflows horizontally (no fixed widths outside the
///   sidebar/rail; tables switch to cards instead of scrolling
///   sideways).
const double kWebDrawerBreakpoint = 700;
const double kWebRailBreakpoint = 900;
const double kWebStatTwoColBreakpoint = 1000;
const double kWebStatOneColBreakpoint = 560;

/// The control center's sections (mockup sidebar order).
enum ControlCenterSection {
  overview,
  board,
  crew,
  hours,
  reports,
  requests,
  sites,
  settings,
  chats,
}

/// Ask the shell to show a section. [siteId] opens the Board
/// filtered to that site; [query] opens the Board with that
/// search text.
typedef WebNavigate = void Function(
  ControlCenterSection section, {
  String? siteId,
  String? query,
});

/// A card in the control center's surface colour, with the
/// standard border and radius.
class WebCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const WebCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: tokens.border),
      ),
      child: child,
    );
  }
}

/// A small coloured pill (statuses, badges, counts).
class WebPill extends StatelessWidget {
  final String label;
  final Color color;
  const WebPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// The pill for a task status, in the status colours.
Widget webTaskStatusPill(
    AppStrings s, AppColors tokens, TaskStatus status) {
  final (String label, Color color) = switch (status) {
    TaskStatus.done => (s.done, tokens.statusDone),
    TaskStatus.inProgress => (s.inProgress, tokens.statusInProgress),
    TaskStatus.blocked => (s.blocked, tokens.statusBlocked),
    TaskStatus.toConfirm => (s.toConfirm, tokens.statusToConfirm),
    TaskStatus.paused => (s.paused, tokens.statusPaused),
    TaskStatus.todo => (s.toDo, tokens.statusTodo),
  };
  return WebPill(label: label, color: color);
}

/// One overview stat: a label, a big value, and an optional
/// sub-line.
class WebStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;
  const WebStatCard({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  TextStyle(fontSize: 13, color: tokens.textSecondary)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: valueColor ?? tokens.textPrimary,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!,
                style: TextStyle(
                    fontSize: 13, color: tokens.textSecondary)),
          ],
        ],
      ),
    );
  }
}

/// A row of stat cards that reflows with the width: 4 columns
/// on a wide desktop, 2 below 1000px, 1 below 560px (phones).
class WebStatGrid extends StatelessWidget {
  final List<Widget> cards;
  const WebStatGrid({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final cols = width >= kWebStatTwoColBreakpoint
          ? 4
          : width >= kWebStatOneColBreakpoint
              ? 2
              : 1;
      const gap = 14.0;
      final cardWidth = (width - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children:
            cards.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
      );
    });
  }
}

/// A table that becomes stacked cards on phones: on wide
/// screens it renders [headers] + one row per [rows] entry; on
/// narrow screens (< 700px) each row becomes a card whose first
/// cell is the title and the rest are labelled lines, so nothing
/// ever scrolls sideways. [flex] is the per-column flex on wide
/// (default 1 each). [onRowTap] fires for the tapped row index
/// in both modes.
class WebResponsiveTable extends StatelessWidget {
  final List<String> headers;
  final List<List<Widget>> rows;
  final List<int>? flex;
  final void Function(int index)? onRowTap;
  final String? emptyText;
  const WebResponsiveTable({
    super.key,
    required this.headers,
    required this.rows,
    this.flex,
    this.onRowTap,
    this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            emptyText ?? '',
            style: TextStyle(color: tokens.textSecondary),
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < kWebDrawerBreakpoint) {
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _cardRow(context, tokens, i),
              ),
          ],
        );
      }
      return Column(
        children: [
          _tableRow(context, tokens, headers.map((h) => Text(
                h.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: tokens.textTertiary,
                ),
              )).toList()),
          Divider(height: 1, color: tokens.border),
          for (var i = 0; i < rows.length; i++) ...[
            _tableRow(context, tokens, rows[i], index: i),
            if (i < rows.length - 1)
              Divider(height: 1, color: tokens.border),
          ],
        ],
      );
    });
  }

  Widget _tableRow(BuildContext context, AppColors tokens,
      List<Widget> cells,
      {int? index}) {
    final flexes = flex ?? List.filled(cells.length, 1);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          for (var j = 0; j < cells.length; j++)
            Expanded(
              flex: flexes[j.clamp(0, flexes.length - 1)],
              child: Padding(
                padding: EdgeInsets.only(right: j < cells.length - 1 ? 12 : 0),
                child: cells[j],
              ),
            ),
        ],
      ),
    );
    final tap = onRowTap;
    if (index == null || tap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => tap(index),
        child: row,
      ),
    );
  }

  Widget _cardRow(BuildContext context, AppColors tokens, int index) {
    final cells = rows[index];
    final content = WebCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cells[0],
          for (var j = 1; j < cells.length; j++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      headers[j],
                      style: TextStyle(
                          fontSize: 12, color: tokens.textTertiary),
                    ),
                  ),
                  Expanded(child: cells[j]),
                ],
              ),
            ),
        ],
      ),
    );
    final tap = onRowTap;
    if (tap == null) return content;
    return InkWell(
      onTap: () => tap(index),
      borderRadius: BorderRadius.circular(13),
      child: content,
    );
  }
}

/// A section heading inside a view: title, optional subtitle,
/// and an optional trailing action.
class WebSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const WebSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                      fontSize: 13, color: tokens.textSecondary),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

/// The content padding for a control-center view: roomy on
/// desktop, tighter on phones so the content still breathes
/// without wasting a narrow screen.
EdgeInsets webContentPadding(double width) {
  if (width < kWebDrawerBreakpoint) {
    return const EdgeInsets.fromLTRB(16, 16, 16, 28);
  }
  return const EdgeInsets.fromLTRB(28, 20, 28, 32);
}

String webTime(DateTime d) => DateFormat('HH:mm').format(d);

String webDay(DateTime d) => DateFormat('EEE, MMM d').format(d);

/// Hours as "7 h 32 min" instead of a decimal ("7.5") — the same
/// shared helper the phone Hours screen and profile use, so the
/// web shows minutes too. (The CSV export stays numeric decimals
/// on purpose, so spreadsheet sums keep working.)
String webHours(double h) => formatHoursMinutes(h);
