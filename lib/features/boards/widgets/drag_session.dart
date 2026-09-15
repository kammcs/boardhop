import 'dart:async';

import 'package:flutter/material.dart' hide Durations;
import 'package:flutter/services.dart';

import '../../../theme/theme.dart';

/// Height of a board column header at text scale 1 ([KanbanColumnHeader]).
const double kBoardHeaderHeight = 52;

/// The column header's height at the current text scale.
///
/// It is not decoration: the vertical edge auto-scroll band starts below the
/// header, so a header that grew with the user's text size while this stayed
/// at 52 would trigger the scroll while the pointer was still over the
/// header (r2 §6). The repo's idiom for "how much bigger is text now" is
/// `textScaler.scale(14) / 14` (`project_home_page.dart`, `search_page.dart`);
/// the cap keeps the band sane at AX5.
double boardHeaderHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  return kBoardHeaderHeight * scale.clamp(1.0, 3.0);
}

/// The drag mechanics the Kanban board and the sprint taskboard grid share.
///
/// The session is owned by the [State] rather than by the
/// [LongPressDraggable] on purpose. Once edge auto-scroll carries the source
/// column (or the card's own slot) out of a lazy list, Flutter unmounts that
/// draggable and silently drops its `onDragUpdate`/`onDragEnd` callbacks,
/// while the drag avatar and the drop keep working. A [Listener] around the
/// whole board sees the pointer anyway, so that is where the session lives.
///
/// A widget mixes this in, wraps its subtree in [dragListener], calls
/// [startDragSession] / [endDragSession] from its draggables and
/// [hoverDragSlot] from its drop targets, and implements [onDragAutoScroll]
/// to move whichever scrollers it owns.
mixin DragSession<W extends StatefulWidget> on State<W> {
  /// Distance from an edge at which auto-scroll starts.
  static const double edge = 64;

  /// Logical pixels per 16 ms tick at the very edge.
  static const double maxSpeed = 16;

  static const Duration tickInterval = Duration(milliseconds: 16);

  Timer? _autoScroll;
  Offset? _pointer;
  Object? _hoverSlot;
  bool _dragging = false;

  /// Whether a drag is in flight.
  bool get dragging => _dragging;

  /// Called when the session starts and when it ends, for the widget's own
  /// `onDragStart` / `onDragEnd` callbacks and any state it keeps.
  void onDragSessionChanged(bool dragging) {}

  /// Called every [tickInterval] while a drag is running, with the pointer
  /// in this state's own coordinate space and the size of its render box.
  void onDragAutoScroll(Offset local, Size size);

  void startDragSession() {
    if (_dragging) return;
    _dragging = true;
    onDragSessionChanged(true);
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(tickInterval, _tick);
  }

  void endDragSession() {
    if (!_dragging) return;
    _dragging = false;
    _autoScroll?.cancel();
    _autoScroll = null;
    _pointer = null;
    _hoverSlot = null;
    onDragSessionChanged(false);
  }

  /// Pointer up reaches the [Listener] before the gesture recognizers route
  /// it to the drag avatar, so the session end is deferred until after the
  /// drop has been delivered.
  void releaseDragPointer() {
    if (_dragging) scheduleMicrotask(endDragSession);
  }

  /// One selection tick when the dragged card would land somewhere new.
  /// [slot] is whatever identifies a landing place to the caller.
  void hoverDragSlot(Object slot) {
    if (_hoverSlot == slot) return;
    _hoverSlot = slot;
    HapticFeedback.selectionClick();
  }

  void _tick(Timer _) {
    final pointer = _pointer;
    final box = context.findRenderObject() as RenderBox?;
    if (pointer == null || box == null || !box.hasSize) return;
    onDragAutoScroll(box.globalToLocal(pointer), box.size);
  }

  /// Scroll speed for a pointer [depth] logical pixels inside the band.
  static double dragSpeed(double depth) =>
      (depth / edge).clamp(0.0, 1.0) * maxSpeed;

  /// Signed auto-scroll delta for a pointer at [position] on an axis whose
  /// content runs from [start] to [end]; zero away from both edges.
  static double dragScrollDelta(double position, double start, double end) {
    if (position < start + edge) return -dragSpeed(start + edge - position);
    if (position > end - edge) return dragSpeed(position - (end - edge));
    return 0;
  }

  /// Jumps [controller] by [delta], clamped to its extent. A jump, not an
  /// animation: this runs every 16 ms and the pointer sets the pace.
  static void dragScrollBy(ScrollController controller, double delta) {
    if (delta == 0 || !controller.hasClients) return;
    final pos = controller.position;
    final target = (pos.pixels + delta).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    if (target != pos.pixels) controller.jumpTo(target);
  }

  /// Wraps the board so the session sees the pointer even after the
  /// draggable that started it has been unmounted by auto-scroll.
  Widget dragListener({required Widget child}) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerMove: (e) {
      if (_dragging) _pointer = e.position;
    },
    onPointerUp: (_) => releaseDragPointer(),
    onPointerCancel: (_) => releaseDragPointer(),
    child: child,
  );

  @override
  void dispose() {
    _autoScroll?.cancel();
    _autoScroll = null;
    super.dispose();
  }
}

/// Animated insertion gap shown above the slot a dragged card would land in.
class DragGap extends StatelessWidget {
  const DragGap({super.key, required this.open, this.minHeight = 0});

  final bool open;

  /// Height when closed: a trailing drop zone keeps some height so the end
  /// of a column stays reachable.
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: Durations.fast,
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
