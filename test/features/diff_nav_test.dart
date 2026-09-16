import 'package:boardhop/features/pull_requests/diff/diff_cursor.dart';
import 'package:boardhop/features/pull_requests/diff/diff_model.dart';
import 'package:boardhop/features/pull_requests/diff/diff_nav_pill.dart';
import 'package:boardhop/features/pull_requests/diff/diff_view.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'diff_page_harness.dart';

/// Whether the floating pill is slid away and deaf to taps (R6).
bool pillHidden(WidgetTester tester) =>
    tester
        .widget<AnimatedSlide>(
          find.ancestor(
            of: find.byType(DiffNavPill),
            matching: find.byType(AnimatedSlide),
          ),
        )
        .offset !=
    Offset.zero;

/// R5–R7 and R16's shortcuts: what the ▲▼ control stops at, what the
/// indicator says, and what the arrows become at the ends of a file.
void main() {
  group('DiffCursor', () {
    const stops = [3, 9, 14];

    test('nothing jumped to yet: ▼ goes to the first stop, ▲ to the last', () {
      const cursor = DiffCursor(mode: DiffNavMode.changes, stops: stops);
      expect(cursor.indicator, '– / 3');
      expect(cursor.nextPosition, 0);
      expect(cursor.previousPosition, 2);
    });

    test('the indicator counts from one', () {
      const cursor = DiffCursor(
        mode: DiffNavMode.changes,
        stops: stops,
        position: 1,
      );
      expect(cursor.indicator, '2 / 3');
      expect(cursor.nextPosition, 2);
      expect(cursor.previousPosition, 0);
    });

    test('the position falls back to the topmost stop on screen', () {
      const cursor = DiffCursor(mode: DiffNavMode.changes, stops: stops);
      expect(cursor.resolvedFrom(8, 20).position, 1);
      // Nothing in view leaves it unknown rather than guessing.
      expect(cursor.resolvedFrom(20, 30).position, isNull);
      // A jump wins over the viewport.
      expect(cursor.at(0).resolvedFrom(8, 20).position, 0);
    });

    test('at the last stop ▼ names the next file, and ▲ the previous', () {
      const cursor = DiffCursor(
        mode: DiffNavMode.changes,
        stops: stops,
        position: 2,
        nextFile: 'two.dart',
        previousFile: 'zero.dart',
      );
      expect(cursor.downEdge, DiffNavEdge.file);
      expect(cursor.downLabel, 'Next file: two.dart');
      expect(cursor.upEdge, DiffNavEdge.stop);
      expect(cursor.at(0).upLabel, 'Previous file: zero.dart');
    });

    test('at the last file both ends read Back to files', () {
      const cursor = DiffCursor(
        mode: DiffNavMode.changes,
        stops: [4],
        position: 0,
      );
      expect(cursor.downEdge, DiffNavEdge.back);
      expect(cursor.downLabel, 'Back to files');
      expect(cursor.upLabel, 'Back to files');
    });

    test('Files mode steps files, so its own end is the end', () {
      const cursor = DiffCursor(
        mode: DiffNavMode.files,
        stops: [0, 1],
        position: 1,
        nextFile: null,
        previousFile: 'one.dart',
      );
      expect(cursor.downEdge, DiffNavEdge.back);
      expect(cursor.upEdge, DiffNavEdge.stop);
    });

    test('a file with no stop at all still offers the next file', () {
      const cursor = DiffCursor(
        mode: DiffNavMode.comments,
        nextFile: 'two.dart',
      );
      expect(cursor.isEmpty, isTrue);
      expect(cursor.indicator, '– / 0');
      expect(cursor.downLabel, 'Next file: two.dart');
    });
  });

  group('the stops DiffView publishes', () {
    testWidgets('changes are the hunk rows and comments are the thread '
        'rows, unresolved first', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final controller = DiffViewController();
      addTearDown(controller.dispose);
      final diff = LineDiff.compute(kOneOld, kOneNew);
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            body: DiffView(
              diff: diff,
              controller: controller,
              oldRuns: const [],
              newRuns: const [],
              threads: [
                prThread(id: 1, rightLine: 5, status: 'fixed'),
                prThread(id: 2, rightLine: 2),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Three changed lines, each its own run.
      expect(controller.stops.changes, hasLength(diff.hunks));
      expect(controller.stops.changes, hasLength(3));
      expect(
        controller.stops.changes,
        orderedEquals(List<int>.of(controller.stops.changes)..sort()),
      );
      // The active thread comes first even though it sits higher up the
      // file than the resolved one is low (R5).
      expect(controller.stops.comments, hasLength(2));
      expect(
        controller.stops.comments.first,
        lessThan(controller.stops.comments.last),
      );
    });

    testWidgets('a resolved thread is stepped last', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final controller = DiffViewController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            body: DiffView(
              diff: LineDiff.compute(kOneOld, kOneNew),
              controller: controller,
              oldRuns: const [],
              newRuns: const [],
              threads: [
                prThread(id: 1, rightLine: 2, status: 'fixed'),
                prThread(id: 2, rightLine: 8),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Row order would be resolved (line 2) then active (line 8); visit
      // order is the other way around.
      expect(
        controller.stops.comments.first,
        greaterThan(controller.stops.comments.last),
      );
    });
  });

  group('the pill on the page', () {
    testWidgets('names the mode and counts the changes', (tester) async {
      await pumpDiffPage(tester);
      expect(find.byType(DiffNavPill), findsOneWidget);
      // The whole short file is on screen, so the cursor reads its place
      // from the viewport rather than waiting for a jump (R6).
      expect(find.text('1 / 3 · Changes'), findsOneWidget);
    });

    testWidgets('▼ walks the changes and the indicator follows', (
      tester,
    ) async {
      await pumpDiffPage(tester);
      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3 · Changes'), findsOneWidget);

      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3 · Changes'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3 · Changes'), findsOneWidget);
    });

    testWidgets('the mode menu switches to Comments and counts them', (
      tester,
    ) async {
      await pumpDiffPage(
        tester,
        threads: [
          threadJson(id: 42977, rightLine: 2, content: 'on the new side'),
        ],
      );
      await tester.tap(find.textContaining('· Changes'));
      await tester.pumpAndSettle();
      expect(find.text('Changes (3)'), findsOneWidget);
      expect(find.text('Comments (1)'), findsOneWidget);
      expect(find.text('Files (2)'), findsOneWidget);

      // The menu's own fade wrapper keeps the label out of the hit test
      // result; the tap still lands on the item under it.
      await tester.tap(find.text('Comments (1)'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('· Comments'), findsOneWidget);
    });

    testWidgets('at the last change ▼ offers the next file and opens it', (
      tester,
    ) async {
      final harness = await pumpDiffPage(tester);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('3 / 3 · Changes'), findsOneWidget);
      expect(find.text('Next file: two.dart'), findsOneWidget);

      await tester.tap(find.text('Next file: two.dart'));
      await tester.pumpAndSettle();

      // Same page, other file, its blob read and its threads with it.
      expect(find.text('two.dart'), findsOneWidget);
      expect(harness.adapter.itemPaths, contains(kTwoPath));
      expect(find.text('1 / 1 · Changes'), findsOneWidget);
    });

    testWidgets('at the last file the arrows read Back to files and pop', (
      tester,
    ) async {
      await pumpDiffPage(tester, path: kTwoPath);
      // The one change is on screen, so the cursor sits on it and both
      // ends of the file are one tap away.
      expect(find.text('Back to files'), findsWidgets);

      await tester.tap(find.text('Back to files').last);
      await tester.pumpAndSettle();
      expect(find.text('Files tab'), findsOneWidget);
    });

    testWidgets('it hides while a comment is being written', (tester) async {
      await pumpDiffPage(tester);
      expect(pillHidden(tester), isFalse);

      await tester.tap(find.text('2').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Comment on line'), findsOneWidget);
      expect(pillHidden(tester), isTrue);
    });

    testWidgets('a tablet keeps the pair in the app bar instead', (
      tester,
    ) async {
      await pumpDiffPage(
        tester,
        size: const Size(2400, 1600),
        devicePixelRatio: 2,
      );
      expect(find.byType(DiffNavBarControls), findsOneWidget);
      expect(find.byType(DiffNavPill), findsNothing);
      expect(find.textContaining('· Changes'), findsOneWidget);
    });
  });

  group('keyboard shortcuts (R16)', () {
    testWidgets('F7 steps a change and shift+F7 steps back', (tester) async {
      await pumpDiffPage(tester);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.f7), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3 · Changes'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pumpAndSettle();
      expect(find.text('3 / 3 · Changes'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3 · Changes'), findsOneWidget);
    });

    testWidgets('n and p step comments, switching the mode with them', (
      tester,
    ) async {
      await pumpDiffPage(
        tester,
        threads: [
          threadJson(id: 1, rightLine: 2, content: 'first'),
          threadJson(id: 2, rightLine: 5, content: 'second'),
          threadJson(id: 3, rightLine: 8, content: 'third'),
        ],
      );
      // The first thread is on screen, so n steps to the one after it.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3 · Comments'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(find.text('3 / 3 · Comments'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3 · Comments'), findsOneWidget);
    });

    testWidgets('] and [ move between files', (tester) async {
      final harness = await pumpDiffPage(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
      await tester.pumpAndSettle();
      expect(find.text('two.dart'), findsOneWidget);
      expect(harness.adapter.itemPaths, contains(kTwoPath));

      await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
      await tester.pumpAndSettle();
      expect(find.text('one.dart'), findsOneWidget);
    });

    testWidgets('a shortcut key typed into a comment is just a letter', (
      tester,
    ) async {
      await pumpDiffPage(tester);
      await tester.tap(find.text('2').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Comment on line'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'n');
      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();

      // Still composing, still on the same file: nothing navigated.
      expect(find.textContaining('Comment on line'), findsOneWidget);
      expect(find.text('one.dart'), findsOneWidget);
      // And the key was left alone rather than swallowed, so the letter
      // reaches the field: an action that merely does nothing still
      // consumes the key, which ate every `n` typed on the iPad
      // (2026-09-16).
      expect(handled, isFalse);
    });
  });

  testWidgets('?line= opens the file on that line (research/22 §4.4)', (
    tester,
  ) async {
    await pumpDiffPage(tester, line: 8);
    // The jump is silent; what it must not do is fail or change the file.
    expect(find.text('one.dart'), findsOneWidget);
    expect(find.text('HOTEL'), findsOneWidget);
  });
}
