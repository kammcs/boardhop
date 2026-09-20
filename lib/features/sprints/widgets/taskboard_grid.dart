import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/work_item.dart';
import '../../../theme/theme.dart';
import '../../boards/widgets/drag_session.dart';
import '../../boards/widgets/kanban_board.dart';
import '../../work_items/widgets/work_item_visuals.dart';
import 'sprint_format.dart';
import '../../../data/models/sprint.dart';
import 'task_card_sheet.dart';

/// Where a task belongs: the index in `columns`, or -1 when the placement
/// rule cannot put it anywhere (a state no column maps). The page supplies
/// it from the repository's `columnFor`, so the grid never re-derives the
/// column rule.
typedef TaskboardColumnOf = int Function(WorkItem task);

/// [toIndex] is the index in the destination cell **after** the card has
/// been removed from its source — the convention `KanbanBoard.onMove`
/// already uses, so a page can share one move handler.
typedef TaskboardMoveCallback = void Function(
  WorkItem card,
  int fromRow,
  int fromColumn,
  int toRow,
  int toColumn,
  int toIndex,
);

/// The tablet taskboard: rows (requirements) by columns (states) as one
/// grid (research/18 S5, r2 §4).
///
/// The shape is deliberate and not a `KanbanBoard` with an extra axis:
///
/// * **One vertical scroller** for the whole grid, so a drag has one
///   vertical auto-scroll target instead of one per cell, and the rows of
///   every column stay lined up.
/// * **Row headers span the viewport, not the grid.** A frozen left column
///   would eat a quarter of an iPad for titles (r2 §4). Instead the whole
///   grid scrolls sideways and each row header counter-translates by the
///   scroll offset, so it stays put while its cells move under it.
/// * **Horizontal scroll is the overflow behaviour.** Three 320 dp columns
///   fit an iPad in landscape; a team with a Review column, or portrait,
///   scrolls.
/// * **Cells are as tall as the tallest in the row** ([IntrinsicHeight]),
///   so the column bands read as a grid. Rows hold a handful of tasks, so
///   the intrinsic pass is cheap.
///
/// The drag mechanics come from [DragSession], the same code the Kanban
/// board runs.
class TaskboardGrid extends StatefulWidget {
  const TaskboardGrid({
    super.key,
    required this.columns,
    required this.rows,
    required this.columnOf,
    required this.cardBuilder,
    required this.visuals,
    required this.onMove,
    this.onAddTask,
    this.onCardTap,
    this.onCardLongPress,
    this.onRowTap,
    this.canDrag = true,
    this.onDragStart,
    this.onDragEnd,
  });

  final List<TaskboardColumn> columns;

  /// Rows in rank order. The Unparented row (a null `parent`) is pinned
  /// first by the caller, as the web does.
  final List<SprintRow> rows;
  final TaskboardColumnOf columnOf;
  final Widget Function(BuildContext context, WorkItem card, bool dragging)
  cardBuilder;
  final WorkItemVisuals visuals;
  final TaskboardMoveCallback onMove;

  /// The row header's `+`: a new task under that requirement.
  final ValueChanged<SprintRow>? onAddTask;
  final ValueChanged<WorkItem>? onCardTap;

  /// The tap-to-move sheet (r2 §5.2). Drag is never the only path.
  final ValueChanged<WorkItem>? onCardLongPress;
  final ValueChanged<SprintRow>? onRowTap;
  final bool canDrag;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  @override
  State<TaskboardGrid> createState() => _TaskboardGridState();
}

class _TaskboardGridState extends State<TaskboardGrid>
    with DragSession<TaskboardGrid> {
  static const _gap = Spacing.md;

  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  final _headerKey = GlobalKey();
  final _collapsed = <String>{};

  double _columnWidth = 320;
  double _padLeft = Spacing.lg;

  /// The gap between two columns, grown to the keep-out band on an active
  /// vertical crease so a fold never falls through a cell (research/23 D3).
  double _gapWidth = _gap;

  /// Cells, `[row][column]`, rebuilt each frame from [TaskboardGrid.rows]
  /// and `columnOf`. Cheap (a sprint is tens of tasks) and it keeps the
  /// grid free of any cached placement that could go stale under a move.
  late List<List<List<WorkItem>>> _cells;

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  void onDragSessionChanged(bool dragging) {
    if (dragging) {
      widget.onDragStart?.call();
    } else {
      widget.onDragEnd?.call();
    }
  }

  /// The header strip's real height, measured rather than assumed: it grows
  /// with the text scale and with a column subtitle, and it is the top edge
  /// of the vertical auto-scroll band.
  double get _headerHeight {
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    return box != null && box.hasSize
        ? box.size.height
        : boardHeaderHeight(context);
  }

  @override
  void onDragAutoScroll(Offset local, Size size) {
    DragSession.dragScrollBy(
      _horizontal,
      DragSession.dragScrollDelta(local.dx, 0, size.width),
    );
    DragSession.dragScrollBy(
      _vertical,
      DragSession.dragScrollDelta(local.dy, _headerHeight, size.height),
    );
  }

  (int, int, int)? _locate(WorkItem card) {
    for (var r = 0; r < _cells.length; r++) {
      for (var c = 0; c < _cells[r].length; c++) {
        final i = _cells[r][c].indexWhere((x) => x.id == card.id);
        if (i >= 0) return (r, c, i);
      }
    }
    return null;
  }

  /// [slot] is the index in the destination cell before the card is removed
  /// from wherever it came from.
  void _drop(WorkItem card, int toRow, int toColumn, int slot) {
    final from = _locate(card);
    if (from == null) return;
    final (fromRow, fromColumn, fromIndex) = from;
    var index = slot;
    final sameCell = fromRow == toRow && fromColumn == toColumn;
    if (sameCell && fromIndex < slot) index -= 1;
    if (sameCell && fromIndex == index) return;
    HapticFeedback.mediumImpact();
    widget.onMove(card, fromRow, fromColumn, toRow, toColumn, index);
  }

  void _moveTo(WorkItem card, int toColumn) {
    final from = _locate(card);
    if (from == null) return;
    final (fromRow, fromColumn, fromIndex) = from;
    if (fromColumn == toColumn) return;
    widget.onMove(
      card,
      fromRow,
      fromColumn,
      fromRow,
      toColumn,
      _cells[fromRow][toColumn].length,
    );
  }

  bool _isCollapsed(SprintRow row) => _collapsed.contains(sprintRowKey(row));

  void _toggle(SprintRow row) {
    final key = sprintRowKey(row);
    setState(() {
      if (!_collapsed.remove(key)) _collapsed.add(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    _cells = [
      for (final row in widget.rows)
        [
          for (var c = 0; c < widget.columns.length; c++)
            [
              for (final task in row.tasks)
                if (widget.columnOf(task) == c) task,
            ],
        ],
    ];
    return dragListener(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _columnWidth = kanbanColumnWidth(
            constraints.maxWidth,
            textScale: boardTextScale(context),
          );
          // The horizontal safe-area padding is the shell's floating glass
          // rail on Apple tablets: the grid rests clear of it and scrolls
          // under it, as the Kanban board does.
          final inset = MediaQuery.paddingOf(context);
          _padLeft = Spacing.lg + inset.left;
          final padRight = Spacing.lg + inset.right;
          final band = creaseInBox(context, constraints);
          final onCrease = isVerticalCrease(band);
          _gapWidth = onCrease ? band!.width : _gap;
          final pitch = _columnWidth + _gapWidth;
          if (onCrease) {
            // As on the Kanban board: the leading padding grows until a
            // column boundary lands on the band with the grid unscrolled,
            // and zero is then one of the snap lattice's rest positions.
            final steps = ((band!.right - _padLeft) / pitch).floor();
            if (steps >= 0) _padLeft = band.right - steps * pitch;
          }
          final viewport = constraints.maxWidth;
          final gridWidth =
              _padLeft +
              widget.columns.length * pitch -
              _gapWidth +
              padRight;
          return SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            // A column boundary rests on the crease, as on the Kanban
            // board, so the fold falls in the gap between two columns.
            physics: onCrease
                ? ColumnSnapPhysics(pitch: pitch, origin: _padLeft - band!.right)
                : null,
            child: SizedBox(
              width: gridWidth < viewport ? viewport : gridWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KeyedSubtree(key: _headerKey, child: _headerStrip(padRight)),
                  Expanded(
                    child: ListView.builder(
                      controller: _vertical,
                      // Short grids must still overscroll for
                      // pull-to-refresh, and the page's RefreshIndicator
                      // looks for a depth-1 vertical notification — which
                      // is what this list is, inside the horizontal
                      // scroller.
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(
                        bottom: Spacing.xl + inset.bottom,
                      ),
                      itemCount: widget.rows.length,
                      itemBuilder: (context, r) =>
                          _row(r, viewport, padRight, inset),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Column headers: pinned above the vertical scroller, scrolling sideways
  /// with the cells. Count and remaining sum come from every row at once.
  Widget _headerStrip(double padRight) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(_padLeft, Spacing.sm, padRight, Spacing.sm),
      // A Column gives its children unbounded height, so the equal-height
      // Row needs its own intrinsic pass.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var c = 0; c < widget.columns.length; c++) ...[
              if (c > 0) SizedBox(width: _gapWidth),
              SizedBox(
                width: _columnWidth,
                child: Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: Radii.card,
                  clipBehavior: Clip.antiAlias,
                  child: KanbanColumnHeader(
                    column: KanbanColumnData<WorkItem>(
                      id: widget.columns[c].name,
                      title: widget.columns[c].name,
                      cards: _columnCards(c),
                      subtitle: _columnSubtitle(c),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<WorkItem> _columnCards(int c) => [for (final row in _cells) ...row[c]];

  String? _columnSubtitle(int c) {
    var sum = 0.0;
    for (final row in _cells) {
      for (final task in row[c]) {
        sum += task.field<num>(kRemainingWorkField)?.toDouble() ?? 0;
      }
    }
    // `any` is not enough: a task whose Remaining Work was cleared holds a
    // real 0, and `formatRemaining(0)` is the empty string — which left the
    // column header reading " remaining" with no number (iPhone check,
    // P-D).
    final text = formatRemaining(sum);
    return text.isEmpty ? null : '$text remaining';
  }

  Widget _row(int r, double viewport, double padRight, EdgeInsets inset) {
    final row = widget.rows[r];
    final collapsed = _isCollapsed(row);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The row header spans the viewport and counter-translates by the
        // horizontal offset, so it stays in place while the cells scroll.
        AnimatedBuilder(
          animation: _horizontal,
          builder: (context, child) => Transform.translate(
            offset: Offset(_horizontal.hasClients ? _horizontal.offset : 0, 0),
            child: child,
          ),
          child: SizedBox(
            width: viewport,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                _padLeft,
                Spacing.sm,
                Spacing.lg + inset.right,
                Spacing.xs,
              ),
              child: TaskboardRowHeader(
                row: row,
                visuals: widget.visuals,
                collapsed: collapsed,
                columnCounts: collapsed
                    ? [for (final cell in _cells[r]) cell.length]
                    : const [],
                onToggle: () => _toggle(row),
                onAddTask: widget.onAddTask == null
                    ? null
                    : () => widget.onAddTask!(row),
                onTap: widget.onRowTap == null || row.parent == null
                    ? null
                    : () => widget.onRowTap!(row),
              ),
            ),
          ),
        ),
        if (!collapsed)
          Padding(
            padding: EdgeInsets.fromLTRB(_padLeft, 0, padRight, Spacing.sm),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < widget.columns.length; c++) ...[
                    if (c > 0) SizedBox(width: _gapWidth),
                    SizedBox(width: _columnWidth, child: _cell(r, c)),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _cell(int r, int c) {
    final scheme = Theme.of(context).colorScheme;
    final cards = _cells[r][c];
    return DragTarget<WorkItem>(
      onWillAcceptWithDetails: (_) => widget.canDrag,
      onMove: (_) => hoverDragSlot((r, c, cards.length)),
      onAcceptWithDetails: (d) => _drop(d.data, r, c, cards.length),
      builder: (context, candidates, _) => Material(
        color: scheme.surfaceContainerLow,
        borderRadius: Radii.card,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < cards.length; i++) _slot(r, c, i, cards[i]),
              // Trailing drop zone: an empty cell still has to be a target.
              DragGap(
                open: candidates.isNotEmpty,
                minHeight: cards.isEmpty ? 56 : 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slot(int r, int c, int i, WorkItem card) {
    final view = Semantics(
      customSemanticsActions: widget.canDrag
          ? taskMoveSemanticsActions(
              columns: widget.columns,
              type: card.type,
              currentColumn: c,
              onMoveTo: (to) => _moveTo(card, to),
            )
          : const {},
      child: GestureDetector(
        onTap: widget.onCardTap == null ? null : () => widget.onCardTap!(card),
        onLongPress: widget.onCardLongPress == null || widget.canDrag
            ? null
            : () => widget.onCardLongPress!(card),
        child: widget.cardBuilder(context, card, false),
      ),
    );
    final target = DragTarget<WorkItem>(
      onWillAcceptWithDetails: (d) => widget.canDrag && d.data.id != card.id,
      onMove: (_) => hoverDragSlot((r, c, i)),
      onAcceptWithDetails: (d) => _drop(d.data, r, c, i),
      builder: (context, candidates, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DragGap(open: candidates.isNotEmpty),
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: view,
          ),
        ],
      ),
    );
    if (!widget.canDrag) {
      return KeyedSubtree(key: ValueKey(card.id), child: target);
    }
    return LongPressDraggable<WorkItem>(
      key: ValueKey(card.id),
      data: card,
      delay: const Duration(milliseconds: 220),
      hapticFeedbackOnStart: true,
      onDragStarted: startDragSession,
      onDragEnd: (_) => endDragSession(),
      feedback: SizedBox(
        width: _columnWidth - Spacing.sm * 2,
        child: widget.cardBuilder(context, card, true),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: view),
      child: target,
    );
  }
}

/// A row header: the requirement (or Unparented) spanning the grid's width,
/// with the collapse chevron and the `+` that adds a task under it.
///
/// Public so the phone's selected-story strip can show the same line.
class TaskboardRowHeader extends StatelessWidget {
  const TaskboardRowHeader({
    super.key,
    required this.row,
    required this.visuals,
    this.collapsed = false,
    this.columnCounts = const [],
    this.onToggle,
    this.onAddTask,
    this.onTap,
  });

  final SprintRow row;
  final WorkItemVisuals visuals;
  final bool collapsed;

  /// Per-column task counts, shown only while collapsed so a folded row
  /// still says where its work sits (`3 · 1 · 2`, as the web does).
  final List<int> columnCounts;
  final VoidCallback? onToggle;
  final VoidCallback? onAddTask;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final parent = row.parent;
    final title = parent?.title ?? 'Unparented';
    final rollup = formatRemaining(row.remaining);
    final meta = <String>[
      if (parent != null) '${parent.type} ${parent.id}',
      formatTaskCount(row.tasks.length),
      if (rollup.isNotEmpty) '$rollup remaining',
      if (collapsed && columnCounts.isNotEmpty) columnCounts.join(' · '),
    ];
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: Radii.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.sm,
            Spacing.sm,
            Spacing.xs,
            Spacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: collapsed ? 'Expand row' : 'Collapse row',
                onPressed: onToggle,
                icon: Icon(collapsed ? Icons.chevron_right : Icons.expand_more),
              ),
              Padding(
                padding: const EdgeInsets.only(top: Spacing.md),
                child: parent == null
                    ? Icon(
                        Icons.inbox_outlined,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      )
                    : Icon(
                        visuals.typeIcon(parent),
                        size: 18,
                        color: visuals.typeColor(context, parent),
                      ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: Spacing.xs),
                      // A Wrap so the id, the count and the rollup drop to
                      // a second line at xxxL instead of overflowing.
                      Wrap(
                        spacing: Spacing.sm,
                        runSpacing: Spacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (parent != null)
                            _StateChip(item: parent, visuals: visuals),
                          for (final m in meta)
                            Text(
                              m,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      if (parent == null && row.tasks.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: Spacing.xs),
                          child: Text(
                            'These tasks have no parent in this sprint.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (onAddTask != null)
                IconButton(
                  tooltip: 'Add task',
                  onPressed: onAddTask,
                  icon: const Icon(Icons.add),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.item, required this.visuals});

  final WorkItem item;
  final WorkItemVisuals visuals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StateDot(color: visuals.stateColor(context, item)),
        const SizedBox(width: Spacing.xs),
        Text(item.state, style: theme.textTheme.labelMedium),
      ],
    );
  }
}
