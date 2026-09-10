import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/theme.dart';

/// One column of a [KanbanBoard].
class KanbanColumnData<T extends Object> {
  const KanbanColumnData({
    required this.id,
    required this.title,
    required this.cards,
    this.accent,
    this.wipLimit,
    this.subtitle,
    this.count,
  });

  final String id;
  final String title;
  final List<T> cards;

  /// The team's column color from the API, tinted for dark mode by the
  /// board (DESIGN.md §3).
  final Color? accent;
  final int? wipLimit;
  final String? subtitle;

  /// Count to show in the header when it differs from [cards] (a split
  /// column shows the whole column's count against its limit).
  final int? count;
}

typedef KanbanCardBuilder<T> =
    Widget Function(BuildContext context, T card, bool dragging);
typedef KanbanMoveCallback<T> =
    void Function(T card, int fromColumn, int fromIndex, int toColumn, int toIndex);

/// Column width: most of a phone screen so the next column peeks in, capped
/// so tablets show several columns.
double kanbanColumnWidth(double viewportWidth) =>
    (viewportWidth * 0.82).clamp(240.0, 320.0);

/// DESIGN.md §3: API colors are rendered as given in light mode and pulled
/// toward the surface in dark mode instead of being used raw.
Color tintApiColor(BuildContext context, Color api) {
  final scheme = Theme.of(context).colorScheme;
  return switch (Theme.of(context).brightness) {
    Brightness.light => api,
    Brightness.dark => Color.lerp(api, scheme.surface, 0.3)!,
  };
}

/// Kanban board on Flutter's own [LongPressDraggable] and [DragTarget]
/// (spike F4): a horizontal list of vertically scrolling columns, edge
/// auto-scroll on both axes, an insertion gap, and haptics. The parent owns
/// the data and applies [onMove]; the board only reports the gesture.
class KanbanBoard<T extends Object> extends StatefulWidget {
  const KanbanBoard({
    super.key,
    required this.columns,
    required this.cardBuilder,
    required this.keyOf,
    required this.onMove,
    this.onCardTap,
    this.onDragStart,
    this.onDragEnd,
    this.canDrag = true,
  });

  final List<KanbanColumnData<T>> columns;
  final KanbanCardBuilder<T> cardBuilder;
  final Object Function(T card) keyOf;

  /// [toIndex] is the index in the destination list after the card has
  /// been removed from its source.
  final KanbanMoveCallback<T> onMove;
  final ValueChanged<T>? onCardTap;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final bool canDrag;

  @override
  State<KanbanBoard<T>> createState() => _KanbanBoardState<T>();
}

class _KanbanBoardState<T extends Object> extends State<KanbanBoard<T>> {
  static const _edge = 64.0;
  static const _maxSpeed = 16.0; // logical px per 16 ms tick at the edge
  static const _gap = Spacing.md;
  static const _headerHeight = 52.0;

  final _horizontal = ScrollController();
  final Map<String, ScrollController> _vertical = {};
  Timer? _autoScroll;
  Offset? _pointer;
  double _columnWidth = 280;
  (int, int)? _hoverSlot;

  /// The drag session is owned here, not by the [LongPressDraggable]. Once
  /// auto-scroll carries the source column (or the card's own slot) out of
  /// a lazy list, Flutter unmounts that draggable and silently drops its
  /// onDragUpdate/onDragEnd callbacks, while the drag avatar and the drop
  /// keep working. A [Listener] around the board sees the pointer anyway.
  bool _dragging = false;

  ScrollController _verticalFor(String id) =>
      _vertical.putIfAbsent(id, ScrollController.new);

  @override
  void dispose() {
    _autoScroll?.cancel();
    _horizontal.dispose();
    for (final c in _vertical.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _dragStarted() {
    if (_dragging) return;
    _dragging = true;
    widget.onDragStart?.call();
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), _tick);
  }

  void _dragEnded() {
    if (!_dragging) return;
    _dragging = false;
    _autoScroll?.cancel();
    _autoScroll = null;
    _pointer = null;
    _hoverSlot = null;
    widget.onDragEnd?.call();
  }

  /// Pointer up reaches the [Listener] before the gesture recognizers route
  /// it to the drag avatar, so defer the session end until after the drop.
  void _pointerReleased() {
    if (_dragging) scheduleMicrotask(_dragEnded);
  }

  static double _speed(double depth) =>
      (depth / _edge).clamp(0.0, 1.0) * _maxSpeed;

  void _tick(Timer _) {
    final pointer = _pointer;
    final box = context.findRenderObject() as RenderBox?;
    if (pointer == null || box == null || !box.hasSize) return;
    final local = box.globalToLocal(pointer);
    final size = box.size;

    if (_horizontal.hasClients) {
      var dx = 0.0;
      if (local.dx < _edge) {
        dx = -_speed(_edge - local.dx);
      } else if (local.dx > size.width - _edge) {
        dx = _speed(local.dx - (size.width - _edge));
      }
      if (dx != 0) {
        final pos = _horizontal.position;
        _horizontal.jumpTo(
          (pos.pixels + dx).clamp(pos.minScrollExtent, pos.maxScrollExtent),
        );
      }
    }

    final column =
        ((local.dx + _horizontal.offset - Spacing.lg) / (_columnWidth + _gap))
            .floor();
    if (column < 0 || column >= widget.columns.length) return;
    final v = _verticalFor(widget.columns[column].id);
    if (!v.hasClients) return;
    var dy = 0.0;
    final top = _headerHeight + _edge;
    if (local.dy < top) {
      dy = -_speed(top - local.dy);
    } else if (local.dy > size.height - _edge) {
      dy = _speed(local.dy - (size.height - _edge));
    }
    if (dy != 0) {
      final pos = v.position;
      v.jumpTo((pos.pixels + dy).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    }
  }

  void _hover(int column, int slot) {
    final key = (column, slot);
    if (_hoverSlot == key) return;
    _hoverSlot = key;
    HapticFeedback.selectionClick();
  }

  (int, int)? _locate(T card) {
    final key = widget.keyOf(card);
    for (var c = 0; c < widget.columns.length; c++) {
      final cards = widget.columns[c].cards;
      for (var i = 0; i < cards.length; i++) {
        if (widget.keyOf(cards[i]) == key) return (c, i);
      }
    }
    return null;
  }

  /// [slot] is the index in the destination list before the card is removed
  /// from wherever it came from.
  void _drop(T card, int toColumn, int slot) {
    final from = _locate(card);
    if (from == null) return;
    final (fromColumn, fromIndex) = from;
    var index = slot;
    if (fromColumn == toColumn && fromIndex < slot) index -= 1;
    if (fromColumn == toColumn && fromIndex == index) return;
    HapticFeedback.mediumImpact();
    widget.onMove(card, fromColumn, fromIndex, toColumn, index);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerMove: (e) {
        if (_dragging) _pointer = e.position;
      },
      onPointerUp: (_) => _pointerReleased(),
      onPointerCancel: (_) => _pointerReleased(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _columnWidth = kanbanColumnWidth(constraints.maxWidth);
          return ListView.builder(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.sm,
            ),
            itemCount: widget.columns.length,
            itemBuilder: (context, c) => Padding(
              padding: const EdgeInsets.only(right: _gap),
              child: SizedBox(width: _columnWidth, child: _column(c)),
            ),
          );
        },
      ),
    );
  }

  Widget _column(int c) {
    final column = widget.columns[c];
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: Radii.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KanbanColumnHeader(column: column),
          Expanded(
            child: DragTarget<T>(
              onWillAcceptWithDetails: (_) => widget.canDrag,
              onMove: (_) => _hover(c, column.cards.length),
              onAcceptWithDetails: (d) => _drop(d.data, c, column.cards.length),
              builder: (context, candidates, _) => ListView.builder(
                controller: _verticalFor(column.id),
                padding: const EdgeInsets.fromLTRB(
                  Spacing.sm,
                  0,
                  Spacing.sm,
                  Spacing.sm,
                ),
                itemCount: column.cards.length + 1,
                itemBuilder: (context, i) {
                  if (i == column.cards.length) {
                    // Trailing drop zone so the end of a column is reachable.
                    return _Gap(open: candidates.isNotEmpty, minHeight: 72);
                  }
                  return _slot(c, i, column.cards[i]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slot(int c, int i, T card) {
    final view = GestureDetector(
      onTap: widget.onCardTap == null ? null : () => widget.onCardTap!(card),
      child: widget.cardBuilder(context, card, false),
    );
    final target = DragTarget<T>(
      onWillAcceptWithDetails: (d) =>
          widget.canDrag && widget.keyOf(d.data) != widget.keyOf(card),
      onMove: (_) => _hover(c, i),
      onAcceptWithDetails: (d) => _drop(d.data, c, i),
      builder: (context, candidates, _) => Column(
        children: [
          _Gap(open: candidates.isNotEmpty),
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: view,
          ),
        ],
      ),
    );
    if (!widget.canDrag) {
      return KeyedSubtree(key: ValueKey(widget.keyOf(card)), child: target);
    }
    return LongPressDraggable<T>(
      key: ValueKey(widget.keyOf(card)),
      data: card,
      delay: const Duration(milliseconds: 220),
      hapticFeedbackOnStart: true,
      onDragStarted: _dragStarted,
      onDragEnd: (_) => _dragEnded(),
      feedback: SizedBox(
        width: _columnWidth - Spacing.sm * 2,
        child: widget.cardBuilder(context, card, true),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: view),
      child: target,
    );
  }
}

class KanbanColumnHeader extends StatelessWidget {
  const KanbanColumnHeader({super.key, required this.column});

  final KanbanColumnData<Object> column;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = column.count ?? column.cards.length;
    final limit = column.wipLimit ?? 0;
    final over = limit > 0 && count > limit;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        Spacing.md,
        Spacing.sm,
      ),
      child: Row(
        children: [
          if (column.accent != null) ...[
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: tintApiColor(context, column.accent!),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: Spacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  column.title,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                if (column.subtitle != null)
                  Text(
                    column.subtitle!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Tooltip(
            message: limit > 0 ? 'WIP limit $limit' : 'Cards in column',
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: over ? scheme.errorContainer : scheme.surfaceContainerHighest,
                borderRadius: Radii.chip,
              ),
              child: Text(
                limit > 0 ? '$count / $limit' : '$count',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: over ? scheme.onErrorContainer : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated insertion gap shown above the slot the dragged card would land in.
class _Gap extends StatelessWidget {
  const _Gap({required this.open, this.minHeight = 0});

  final bool open;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      height: open ? 96 : minHeight,
      margin: EdgeInsets.only(bottom: open ? Spacing.sm : 0),
      decoration: BoxDecoration(
        color: open ? scheme.primaryContainer.withValues(alpha: 0.5) : null,
        borderRadius: Radii.card,
        border: open ? Border.all(color: scheme.primary, width: 1.5) : null,
      ),
    );
  }
}
