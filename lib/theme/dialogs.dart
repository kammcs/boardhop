// The theme's own motion tokens, not Flutter's `Durations`.
import 'package:flutter/material.dart' hide Durations;

import '../core/display_environment.dart';
import 'tokens.dart';

/// Where a dialog goes when the display is folded: one half of it, never
/// across the fold (research/23 D3).
///
/// [insets] is what reduces the dialog route's box to that half — the
/// route is asked for `useSafeArea: false` and this takes the system's
/// insets off as well, so a dialog on the trailing half still clears the
/// stacked status bar. [alignment] says the same thing for a caller that
/// aligns rather than pads, and [anchor] is the point Flutter's own
/// `DisplayFeatureSubScreen` will use once the iOS engine populates
/// `MediaQuery.displayFeatures` (flutter/flutter#192515) and this wrapper
/// can be deleted.
@immutable
class DialogHalf {
  const DialogHalf({
    required this.half,
    required this.insets,
    required this.constraints,
    required this.alignment,
  });

  /// The usable rectangle, in window coordinates: one half of the display
  /// less the system's insets and a [Spacing.xl] margin.
  final Rect half;

  /// What a full-window box is padded by to become [half].
  final EdgeInsets insets;

  /// [half]'s size, as constraints for the dialog itself.
  final BoxConstraints constraints;

  /// [half]'s centre expressed against the whole window.
  final Alignment alignment;

  /// [half]'s centre in window coordinates.
  Offset get anchor => half.center;
}

/// The box of the widget a dialog is being opened from, in window
/// coordinates, or null when it has not been laid out.
Rect? openerBoxOf(BuildContext context) {
  final object = context.findRenderObject();
  if (object is RenderBox && object.attached && object.hasSize) {
    return object.localToGlobal(Offset.zero) & object.size;
  }
  return null;
}

/// The half of a folded display a dialog opened from [near] belongs on, or
/// null when nothing is folded and dialogs centre on the window as before.
///
/// [near] is the point the dialog was opened from, in window coordinates.
/// Without one [nearBox] is used, or the calling widget's own box, when it
/// is small enough to be a control — a toolbar button knows which half it
/// is on, a whole page does not — and failing that the **trailing** half
/// for a vertical crease and the **lower** half for a horizontal one, the
/// halves nearer the hands.
///
/// [nearBox] is that box measured somewhere else: [showBoardhopDialog]
/// reads it while the opening widget is still on screen and hands it back
/// on every rebuild inside the route, where `context` is the dialog's own
/// full-window box and would answer nothing.
DialogHalf? dialogAlignmentFor(
  BuildContext context, {
  Offset? near,
  Rect? nearBox,
}) {
  final environment = DisplayScope.maybeOf(context);
  final axis = environment?.creaseAxis;
  if (environment == null || axis == null) return null;
  final size = MediaQuery.sizeOf(context);
  final halves = environment.halves(size);
  if (halves.length != 2) return null;

  var spot = near;
  if (spot == null) {
    final box = nearBox ?? openerBoxOf(context);
    if (box != null) {
      final extent = axis == Axis.vertical ? box.width : box.height;
      final window = axis == Axis.vertical ? size.width : size.height;
      if (extent <= window / 2) spot = box.center;
    }
  }
  final chosen = spot != null && halves.first.contains(spot)
      ? halves.first
      : halves.last;

  final inset = MediaQuery.paddingOf(context);
  final safe = Rect.fromLTRB(
    inset.left,
    inset.top,
    size.width - inset.right,
    size.height - inset.bottom,
  );
  var target = chosen.intersect(safe);
  if (target.width > 2 * Spacing.xl && target.height > 2 * Spacing.xl) {
    target = target.deflate(Spacing.xl);
  }
  if (target.isEmpty) return null;
  return DialogHalf(
    half: target,
    insets: EdgeInsets.fromLTRB(
      target.left,
      target.top,
      size.width - target.right,
      size.height - target.bottom,
    ),
    constraints: BoxConstraints(
      maxWidth: target.width,
      maxHeight: target.height,
    ),
    alignment: Alignment(
      size.width == 0 ? 0 : (2 * target.center.dx / size.width) - 1,
      size.height == 0 ? 0 : (2 * target.center.dy / size.height) - 1,
    ),
  );
}

/// [showDialog] with one extra rule: on a half-folded display the dialog
/// centres on **one half** instead of straddling the fold (research/23 D3).
///
/// Every dialog-or-sheet helper in the app goes through this, so no page
/// had to change. With nothing folded — which is every device but an
/// iPhone Duo, and a Duo lying flat — it is [showDialog] unchanged, right
/// down to `useSafeArea`.
///
/// **The placement is live** (phase 4B). It used to be settled here, when
/// the route was shown, so a dialog that was already open when the device
/// was folded stayed across the fold. It is built inside the route now,
/// from [DisplayScope], and moves on the theme's standard motion when the
/// display changes shape under it. The half it moves *to* is still the one
/// it was opened on: [near], or the opening widget's box read here, while
/// that widget is still on screen.
///
/// The box is moved by padding rather than by an alignment, because both
/// have to change at once: a dialog that fills what it is given — the rich
/// text editor — must be resized to the half, not only slid onto it, and
/// an `Align` can only slide. The same padding is the safe area when
/// nothing is folded, which is what `useSafeArea: true` would have put
/// here once and for all.
///
/// Bottom sheets are left alone: they only appear at a compact width,
/// where the window is one half already.
Future<T?> showBoardhopDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Offset? near,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  // Read while the opening widget is still on screen; inside the route
  // `context` is the dialog's own full-window box, which says nothing
  // about which half the caller was on.
  final opener = near == null ? openerBoxOf(context) : null;
  final placement = dialogAlignmentFor(context, near: near, nearBox: opener);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
    // The safe area is part of the placement below, which can change; this
    // one cannot, and a SafeArea on top of a half's insets would take the
    // Duo's 84 pt bar column off the *leading* half as well, which is
    // nowhere near it.
    useSafeArea: false,
    // Only read once by `DisplayFeatureSubScreen`, and only where the
    // engine reports display features at all — never on iOS today
    // (flutter/flutter#192515).
    anchorPoint: placement?.anchor,
    builder: (context) =>
        _DialogPlacement(near: near, nearBox: opener, builder: builder),
  );
}

/// Keeps a dialog on one half of a folded display, and moves it there if
/// the display folds while it is open.
class _DialogPlacement extends StatelessWidget {
  const _DialogPlacement({this.near, this.nearBox, required this.builder});

  final Offset? near;
  final Rect? nearBox;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final placement = dialogAlignmentFor(context, near: near, nearBox: nearBox);
    return AnimatedPadding(
      duration: Durations.normal,
      curve: Motion.standard,
      // Folded: the half, the system's insets already taken off it.
      // Flat: the safe area, exactly where `showDialog` would have put it.
      padding: placement?.insets ?? MediaQuery.paddingOf(context),
      child: ConstrainedBox(
        constraints: placement?.constraints ?? const BoxConstraints(),
        child: Builder(builder: builder),
      ),
    );
  }
}
