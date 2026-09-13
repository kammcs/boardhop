import 'package:boardhop/data/models/pr_check.dart';
import 'package:boardhop/features/pull_requests/widgets/pr_visuals.dart';
import 'package:boardhop/features/work_items/widgets/work_item_field_groups.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:boardhop/theme/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The open findings from the two iOS walkthroughs (NEXT-STEPS step 16),
/// one group each, so a regression names the finding it brings back.
void main() {
  /// The surface a width case needs: a `SizedBox` wider than the tester's
  /// default 800x600 window is clamped to it, so setting only MediaQuery
  /// silently tested the wrong width.
  void surface(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 1376);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host({
    required Widget child,
    double width = 402,
    double textScale = 1,
  }) => MaterialApp(
    theme: BoardhopTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 874),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );

  group('finding g: the detail label column at accessibility sizes', () {
    testWidgets('"Changed" is laid out whole, never broken mid-word', (
      tester,
    ) async {
      // A single word that does not fit its box is wrapped between
      // characters, so a label taller than one line means "Chang / ed".
      for (final scale in [1.0, 1.3, 1.6, 2.0, 3.1]) {
        await tester.pumpWidget(
          host(
            textScale: scale,
            child: const DetailFactRow(label: 'Changed', value: 'today'),
          ),
        );
        final inRow = tester.getSize(find.text('Changed')).height;

        // The same text and scale with all the room it wants: one line.
        await tester.pumpWidget(
          host(
            textScale: scale,
            child: Builder(
              builder: (context) => Text(
                'Changed',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        );
        final oneLine = tester.getSize(find.text('Changed')).height;

        expect(
          inRow,
          closeTo(oneLine, 1),
          reason: 'at ${scale}x "Changed" wrapped inside the label column',
        );
      }
    });

    testWidgets('the column follows the text scale, capped at 2x', (
      tester,
    ) async {
      Future<double> widthAt(double scale) async {
        late double width;
        await tester.pumpWidget(
          host(
            textScale: scale,
            child: Builder(
              builder: (context) {
                width = DetailFactRow.labelWidthFor(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        return width;
      }

      expect(await widthAt(1), DetailFactRow.labelWidth);
      expect(await widthAt(1.5), DetailFactRow.labelWidth * 1.5);
      expect(
        await widthAt(3.1),
        DetailFactRow.labelWidth * 2,
        reason: 'the row is chrome; it cannot grow without limit',
      );
    });

    testWidgets('past the cap the label stacks above its value', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          textScale: 3.1,
          child: const DetailFactRow(label: 'Changed', value: 'today'),
        ),
      );
      expect(
        tester.getRect(find.text('today')).top,
        greaterThanOrEqualTo(tester.getRect(find.text('Changed')).bottom),
        reason: 'two columns are unreadable at this size; stack instead',
      );

      // At the ordinary size it stays a two-column row.
      await tester.pumpWidget(
        host(child: const DetailFactRow(label: 'Changed', value: 'today')),
      );
      final label = tester.getRect(find.text('Changed'));
      final value = tester.getRect(find.text('today'));
      expect(value.left, greaterThanOrEqualTo(label.right - 1));
      expect(value.top, lessThan(label.bottom));
    });
  });

  group('finding h: the snackbar on a wide window', () {
    test('a phone keeps the full-width bar', () {
      final theme = BoardhopTheme.forWindow(BoardhopTheme.light(), 402);
      expect(theme.snackBarTheme.width, isNull);
    });

    test('an iPad caps it so one line does not run the whole window', () {
      final theme = BoardhopTheme.forWindow(BoardhopTheme.light(), 1032);
      expect(theme.snackBarTheme.width, BoardhopTheme.snackBarMaxWidth);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
    });

    testWidgets('the capped bar is narrower than the window and centred', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1032, 1376);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: key,
          theme: BoardhopTheme.light(),
          builder: (context, child) => Theme(
            data: BoardhopTheme.forWindow(
              Theme.of(context),
              MediaQuery.sizeOf(context).width,
            ),
            child: child ?? const SizedBox.shrink(),
          ),
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      key.currentState!.showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      // The visible surface, not the SnackBar element: with a width set,
      // Flutter pads the bar inside a box that still reports the window.
      final bar = tester.getRect(
        find
            .descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(bar.width, BoardhopTheme.snackBarMaxWidth);
      expect(bar.center.dx, closeTo(1032 / 2, 1));
    });
  });

  group('finding k: an optional failing policy', () {
    testWidgets('reads as a warning, not as the blocking red X', (
      tester,
    ) async {
      late Color blockingColor;
      late Color optionalColor;
      await tester.pumpWidget(
        host(
          child: Builder(
            builder: (context) {
              blockingColor = checkColor(
                context,
                PrCheckState.failed,
                isBlocking: true,
              );
              optionalColor = checkColor(
                context,
                PrCheckState.failed,
                isBlocking: false,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        checkIcon(PrCheckState.failed, isBlocking: true),
        Icons.cancel,
      );
      expect(
        checkIcon(PrCheckState.failed, isBlocking: false),
        Icons.warning_amber_rounded,
      );
      expect(
        optionalColor,
        isNot(blockingColor),
        reason: 'an optional failure looked like it stopped the merge',
      );
    });

    testWidgets('a passing check looks the same either way', (tester) async {
      await tester.pumpWidget(
        host(
          child: Builder(
            builder: (context) {
              expect(
                checkColor(context, PrCheckState.succeeded, isBlocking: false),
                checkColor(context, PrCheckState.succeeded, isBlocking: true),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        checkIcon(PrCheckState.succeeded, isBlocking: false),
        checkIcon(PrCheckState.succeeded, isBlocking: true),
      );
    });
  });

  group('iPhone Duo: the two-column threshold', () {
    test("the Duo's inner display gets two columns", () {
      // research/12b: the inner display is regular x regular and
      // ContentColumn yields 903 pt of content there.
      const duoInnerContentWidth = 903.0;
      expect(
        duoInnerContentWidth,
        greaterThanOrEqualTo(ContentColumn.twoColumnMin),
      );
    });

    test('a phone and a small tablet in portrait stay on one column', () {
      // iPhone 17 portrait, and an iPad Pro 11" portrait.
      for (final width in [402.0, 834.0]) {
        expect(
          ContentColumn.widthFor(width),
          lessThan(ContentColumn.twoColumnMin),
          reason: '$width pt should not split into two columns',
        );
      }
    });

    testWidgets('SideBySide splits at the threshold and not below it', (
      tester,
    ) async {
      Future<void> pumpAt(double width) async {
        surface(tester, width);
        await tester.pumpWidget(
          host(
            width: width,
            child: const SideBySide(
              start: [Text('start')],
              end: [Text('end')],
            ),
          ),
        );
      }

      await pumpAt(ContentColumn.twoColumnMin - 1);
      expect(
        tester.getRect(find.text('end')).top,
        greaterThanOrEqualTo(tester.getRect(find.text('start')).bottom),
        reason: 'stacked below the threshold',
      );

      await pumpAt(ContentColumn.twoColumnMin);
      expect(
        tester.getRect(find.text('end')).left,
        greaterThan(tester.getRect(find.text('start')).right),
        reason: 'side by side at the threshold',
      );
    });
  });
}
