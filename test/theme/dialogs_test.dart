import 'dart:async';

import 'package:boardhop/core/display_cutout.dart';
import 'package:boardhop/theme/dialogs.dart';
import 'package:boardhop/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/duo_display.dart';

/// Dialogs on a half-folded display centre on one half and never straddle
/// the fold (research/23 D3).
void main() {
  /// Pumps a page whose button opens a dialog through
  /// [showBoardhopDialog], and hands back the context the wrapper is
  /// called with.
  Future<BuildContext> pump(
    WidgetTester tester, {
    required Size window,
    required EdgeInsets insets,
    DisplayRegions? regions,
    Alignment buttonAt = Alignment.centerRight,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext buttonContext;
    await tester.pumpWidget(
      Duo.scope(
        window: window,
        regions: regions,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(padding: insets),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: buttonAt,
              child: Builder(
                builder: (context) {
                  buttonContext = context;
                  return const SizedBox(width: 48, height: 48);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return buttonContext;
  }

  group('dialogAlignmentFor', () {
    testWidgets('is null when nothing is folded', (tester) async {
      final context = await pump(
        tester,
        window: Duo.wide,
        insets: Duo.wideInsets,
        regions: Duo.flat(Duo.wideBand),
      );
      expect(dialogAlignmentFor(context), isNull);
    });

    testWidgets('takes the half the tap is on', (tester) async {
      final context = await pump(
        tester,
        window: Duo.wide,
        insets: Duo.wideInsets,
        regions: Duo.folded(Duo.wideBand),
      );
      final leading = dialogAlignmentFor(context, near: const Offset(100, 300));
      expect(leading, isNotNull);
      expect(leading!.half.right, lessThanOrEqualTo(Duo.creaseLine));
      expect(leading.alignment.x, lessThan(0));

      final trailing = dialogAlignmentFor(
        context,
        near: const Offset(800, 300),
      );
      expect(trailing!.half.left, greaterThanOrEqualTo(Duo.creaseLine));
      expect(trailing.alignment.x, greaterThan(0));
      // The stacked status bar's 84 pt is off the trailing half, and the
      // margin off both.
      expect(trailing.half.right, closeTo(951 - 84 - Spacing.xl, 0.01));
    });

    testWidgets('falls back to the half the caller sits on', (tester) async {
      // No `near`: the button's own box answers, because it is small
      // enough to be a control rather than a page.
      final context = await pump(
        tester,
        window: Duo.wide,
        insets: Duo.wideInsets,
        regions: Duo.folded(Duo.wideBand),
        buttonAt: Alignment.centerLeft,
      );
      expect(dialogAlignmentFor(context)!.alignment.x, lessThan(0));
    });

    testWidgets('a horizontal crease takes the lower half', (tester) async {
      final context = await pump(
        tester,
        window: Duo.tall,
        insets: Duo.tallInsets,
        regions: Duo.folded(Duo.tallBand),
        buttonAt: Alignment.center,
      );
      final placement = dialogAlignmentFor(context);
      expect(placement, isNotNull);
      expect(placement!.half.top, greaterThanOrEqualTo(Duo.creaseLine));
      expect(placement.alignment.y, greaterThan(0));
    });
  });

  group('showBoardhopDialog', () {
    testWidgets('centres on the window when nothing is folded', (tester) async {
      final context = await pump(
        tester,
        window: Duo.wide,
        insets: Duo.wideInsets,
        regions: Duo.flat(Duo.wideBand),
      );
      unawaited(
        showBoardhopDialog<void>(
          context: context,
          builder: (_) => const Dialog(
            child: SizedBox(width: 400, height: 200, child: Text('picker')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Today's behaviour, untouched: `showDialog`'s own SafeArea centres
      // it in what is left of the window beside the 84 pt bar column.
      final box = tester.getRect(find.text('picker'));
      expect(box.center.dx, closeTo((951 - 84) / 2, 1));
    });

    testWidgets('stays inside one half when folded', (tester) async {
      final context = await pump(
        tester,
        window: Duo.wide,
        insets: Duo.wideInsets,
        regions: Duo.folded(Duo.wideBand),
      );
      unawaited(
        showBoardhopDialog<void>(
          context: context,
          near: const Offset(800, 300),
          builder: (_) => const Dialog(
            child: SizedBox(width: 400, height: 200, child: Text('picker')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final box = tester.getRect(find.byType(Dialog));
      expect(box.left, greaterThanOrEqualTo(Duo.creaseLine));
      // Clear of the system's bar column on that edge.
      expect(box.right, lessThanOrEqualTo(951 - 84));
    });

    testWidgets('a dialog opened on the leading half stays there', (
      tester,
    ) async {
      final context = await pump(
        tester,
        window: Duo.wide,
        insets: Duo.wideInsets,
        regions: Duo.folded(Duo.wideBand),
      );
      unawaited(
        showBoardhopDialog<void>(
          context: context,
          near: const Offset(120, 300),
          builder: (_) => const Dialog(
            child: SizedBox(width: 400, height: 200, child: Text('picker')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(Dialog)).right,
        lessThanOrEqualTo(Duo.creaseLine),
      );
    });
  });
}
