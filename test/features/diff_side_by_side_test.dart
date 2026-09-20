import 'package:boardhop/core/display_cutout.dart';
import 'package:boardhop/features/pull_requests/diff/diff_model.dart';
import 'package:boardhop/features/pull_requests/diff/diff_view.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/duo_display.dart';
import 'diff_page_harness.dart';

/// R16's side-by-side layout: the original on the left, the new file on the
/// right, changed lines facing each other, and every card under the pane it
/// belongs to.
void main() {
  DiffAnchor? tapped;
  DiffAnchor? composer;

  Future<void> pump(
    WidgetTester tester, {
    bool sideBySide = true,
    List<dynamic> threads = const [],
    Size window = const Size(2400, 1600),
    double pixelRatio = 2,
    DisplayRegions? regions,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Duo.scope(
        window: window / pixelRatio,
        regions: regions,
        child: MaterialApp(
          theme: BoardhopTheme.light(),
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: DiffView(
                diff: LineDiff.compute(kOneOld, kOneNew),
                oldRuns: const [],
                newRuns: const [],
                sideBySide: sideBySide,
                canAct: true,
                threads: threads.cast(),
                composer: composer,
                onGutterTap: (anchor) => setState(() {
                  tapped = anchor;
                  composer = anchor;
                }),
                onCancelComposer: () => setState(() => composer = null),
                onPost: (_, _) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    tapped = null;
    composer = null;
  });

  testWidgets('a changed line faces its replacement on the same row', (
    tester,
  ) async {
    await pump(tester);
    final left = tester.getCenter(find.text('bravo'));
    final right = tester.getCenter(find.text('BRAVO'));
    expect(left.dy, right.dy);
    expect(left.dx, lessThan(right.dx));

    // A context line is drawn on both sides.
    expect(find.text('charlie'), findsNWidgets(2));
  });

  testWidgets('the unified layout keeps one column', (tester) async {
    await pump(tester, sideBySide: false);
    final left = tester.getCenter(find.text('bravo'));
    final right = tester.getCenter(find.text('BRAVO'));
    expect(left.dy, lessThan(right.dy));
    expect(find.text('charlie'), findsOneWidget);
  });

  testWidgets('a right-side thread sits under the right pane and a '
      'left-side one under the left (R9)', (tester) async {
    await pump(
      tester,
      threads: [
        prThread(id: 1, rightLine: 2, content: 'on the new side'),
        prThread(id: 2, leftLine: 2, content: 'on the original'),
      ],
    );
    final middle = tester.getSize(find.byType(DiffView)).width / 2;
    expect(
      tester.getCenter(find.textContaining('on the new side')).dx,
      greaterThan(middle),
    );
    expect(
      tester.getCenter(find.textContaining('on the original')).dx,
      lessThan(middle),
    );
  });

  testWidgets('the composer opens under the side that was tapped', (
    tester,
  ) async {
    await pump(tester);
    final middle = tester.getSize(find.byType(DiffView)).width / 2;

    // The left pane's gutter of the removed line.
    await tester.tap(find.text('2').first);
    await tester.pumpAndSettle();
    expect(tapped?.leftSide, isTrue);
    expect(find.text('Comment on line 2 (original)'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Comment on line 2 (original)')).dx,
      lessThan(middle),
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    expect(tapped?.leftSide, isFalse);
    expect(
      tester.getCenter(find.text('Comment on line 2')).dx,
      greaterThan(middle),
    );
  });

  testWidgets('a tablet opens side by side and a phone unified (R16)', (
    tester,
  ) async {
    await pumpDiffPage(
      tester,
      size: const Size(2400, 1600),
      devicePixelRatio: 2,
    );
    expect(tester.widget<DiffView>(find.byType(DiffView)).sideBySide, isTrue);
  });

  testWidgets('a phone opens unified', (tester) async {
    await pumpDiffPage(tester);
    expect(tester.widget<DiffView>(find.byType(DiffView)).sideBySide, isFalse);
  });

  testWidgets('half folded, the two panes land on the two panels', (
    tester,
  ) async {
    // The Duo's inner display in the book pose: the split goes on the
    // fold, with the 40 pt keep-out band as the gap between the panes
    // (research/23 D3), not down the middle of the box.
    await pump(
      tester,
      window: Duo.wide,
      pixelRatio: 1,
      regions: Duo.folded(Duo.wideBand),
    );
    final pairs = tester.widgetList<Row>(
      find.descendant(
        of: find.byType(IntrinsicHeight),
        matching: find.byType(Row),
      ),
    );
    expect(pairs, isNotEmpty);
    final gutters = tester.widgetList<SizedBox>(
      find.descendant(
        of: find.byType(IntrinsicHeight).first,
        matching: find.byType(SizedBox),
      ),
    );
    expect(
      gutters.any((box) => box.width == Duo.wideBand.width),
      isTrue,
      reason: 'the gap between the panes is the keep-out band',
    );
    expect(
      gutters.any((box) => box.width == Duo.wideBand.left),
      isTrue,
      reason: 'the left pane ends where the band begins',
    );
  });

  testWidgets('flat, the split is still down the middle', (tester) async {
    await pump(
      tester,
      window: Duo.wide,
      pixelRatio: 1,
      regions: Duo.flat(Duo.wideBand),
    );
    final gutters = tester.widgetList<SizedBox>(
      find.descendant(
        of: find.byType(IntrinsicHeight).first,
        matching: find.byType(SizedBox),
      ),
    );
    // Half the box, not the band's edge: an inactive division is not a
    // fold (research/23 section 2).
    expect(gutters.any((box) => box.width == Duo.wide.width / 2), isTrue);
    expect(gutters.any((box) => box.width == Duo.wideBand.left), isFalse);
  });
}
