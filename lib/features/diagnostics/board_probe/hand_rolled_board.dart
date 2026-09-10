import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/theme.dart';
import 'board_probe_data.dart';
import 'probe_widgets.dart';

/// Candidate 0: no package. Flutter's own [LongPressDraggable] and
/// [DragTarget] with a horizontal list of vertically scrolling columns,
/// edge auto-scroll on both axes, an insertion gap, and haptics.
class HandRolledBoard extends StatefulWidget {
  const HandRolledBoard({super.key, required this.data, required this.hooks});

  final BoardData data;
  final BoardProbeHooks hooks;

  @override
  State<HandRolledBoard> createState() => _HandRolledBoardState();
}

class _HandRolledBoardState extends State<HandRolledBoard> {
  static const _edge = 64.0;
  static const _maxSpeed = 16.0; // logical px per 16 ms tick at the edge
  static const _gap = Spacing.md;
  static const _headerHeight = 52.0;

  final _horizontal = ScrollController();
  late final List<ScrollController> _vertical = List.generate(
    widget.data.columns.length,
    (_) => ScrollController(),
  );
  Timer? _autoScroll;
  Offset? _pointer;
  double _columnWidth = 280;
  (int, int)? _hoverSlot;

  @override
  void dispose() {
    _autoScroll?.cancel();
    _horizontal.dispose();
    for (final c in _vertical) {
      c.dispose();
    }
    super.dispose();
  }

  /// The drag session is owned here, not by the [LongPressDraggable]. Once
  /// auto-scroll carries the source column (or the card's own slot) out of a
  /// lazy list, Flutter unmounts that draggable and silently drops its
  /// onDragUpdate/onDragEnd callbacks, while the drag avatar and the drop
  /// keep working. A [Listener] around the board sees the pointer regardless.
  bool _dragging = false;

  void _dragStarted() {
    if (_dragging) return;
    _dragging = true;
    widget.hooks.onDragStart();
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
    widget.hooks.onDragEnd();
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
    if (column < 0 || column >= _vertical.length) return;
    final v = _vertical[column];
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

  /// [slot] is the index in the destination list before the card is removed
  /// from wherever it came from.
  void _drop(ProbeCard card, int toColumn, int slot) {
    final from = widget.data.locate(card);
    if (from == null) return;
    final (fromColumn, fromIndex) = from;
    var index = slot;
    if (fromColumn == toColumn && fromIndex < slot) index -= 1;
    HapticFeedback.mediumImpact();
    setState(() {
      widget.hooks.onMove(
        widget.data.move(
          fromColumn: fromColumn,
          fromIndex: fromIndex,
          toColumn: toColumn,
          toIndex: index,
        ),
      );
    });
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
          _columnWidth = probeColumnWidth(constraints.maxWidth);
          return ListView.builder(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.sm,
            ),
            itemCount: widget.data.columns.length,
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
    final column = widget.data.columns[c];
    return ProbeColumnFrame(
      column: column,
      child: DragTarget<ProbeCard>(
        onWillAcceptWithDetails: (_) => true,
        onMove: (_) => _hover(c, column.cards.length),
        onAcceptWithDetails: (d) => _drop(d.data, c, column.cards.length),
        builder: (context, candidates, _) => ListView.builder(
          controller: _vertical[c],
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
    );
  }

  Widget _slot(int c, int i, ProbeCard card) {
    final column = widget.data.columns[c];
    final view = ProbeCardView(card: card, column: column);
    return LongPressDraggable<ProbeCard>(
      key: ValueKey(card.id),
      data: card,
      delay: const Duration(milliseconds: 220),
      hapticFeedbackOnStart: true,
      onDragStarted: _dragStarted,
      onDragEnd: (_) => _dragEnded(),
      feedback: SizedBox(
        width: _columnWidth - Spacing.sm * 2,
        child: ProbeCardView(card: card, column: column, dragging: true),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: view),
      child: DragTarget<ProbeCard>(
        onWillAcceptWithDetails: (d) => d.data.id != card.id,
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
        border: open
            ? Border.all(color: scheme.primary, width: 1.5)
            : null,
      ),
    );
  }
}
