import 'package:boardhop/features/pull_requests/diff/diff_model.dart';
import 'package:boardhop/features/pull_requests/diff/diff_view.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'diff_page_harness.dart';

/// R10: long-press a gutter line and drag to extend, and the composer that
/// opens on release covers the range.
void main() {
  late List<DiffAnchor> anchors;
  DiffAnchor? composer;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: DiffView(
              diff: LineDiff.compute(kOneOld, kOneNew),
              oldRuns: const [],
              newRuns: const [],
              canAct: true,
              composer: composer,
              onGutterTap: (anchor) => setState(() {
                anchors.add(anchor);
                composer = anchor;
              }),
              onCancelComposer: () => setState(() => composer = null),
              onPost: (_, _) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    anchors = [];
    composer = null;
  });

  /// A long press on [from]'s gutter, dragged onto [to]'s, then released.
  Future<void> dragRange(
    WidgetTester tester,
    Finder from,
    Finder to, {
    bool release = true,
  }) async {
    final gesture = await tester.startGesture(tester.getCenter(from));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(to));
    await tester.pump();
    if (!release) return;
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a drag down the new side posts one range', (tester) async {
    await pump(tester);
    // The new-side gutter of line 5 (ECHO) down to line 8 (HOTEL).
    await dragRange(tester, find.text('5').last, find.text('8').last);

    expect(anchors, hasLength(1));
    expect(anchors.single.line, 5);
    expect(anchors.single.last, 8);
    expect(anchors.single.isRange, isTrue);
    expect(anchors.single.leftSide, isFalse);
    expect(find.text('Comment on lines 5–8'), findsOneWidget);
  });

  testWidgets('a drag upwards is the same range', (tester) async {
    await pump(tester);
    await dragRange(tester, find.text('8').last, find.text('5').last);
    expect(anchors.single.line, 5);
    expect(anchors.single.last, 8);
  });

  testWidgets('the original side ranges too', (tester) async {
    await pump(tester);
    await dragRange(tester, find.text('2').first, find.text('5').first);
    expect(anchors.single.leftSide, isTrue);
    expect(anchors.single.line, 2);
    expect(anchors.single.last, 5);
    expect(find.text('Comment on lines 2–5 (original)'), findsOneWidget);
  });

  testWidgets('the two sides never join into one range', (tester) async {
    await pump(tester);
    // Start on the original side, drag onto the new side: the new side is
    // not a target for this drag, so the range stays where it began.
    await dragRange(tester, find.text('5').first, find.text('8').last);
    expect(anchors.single.leftSide, isTrue);
    expect(anchors.single.isRange, isFalse);
  });

  testWidgets('a long press that never moves is a single-line comment', (
    tester,
  ) async {
    await pump(tester);
    await tester.longPress(find.text('5').last);
    await tester.pumpAndSettle();
    expect(anchors.single.isRange, isFalse);
    expect(anchors.single.line, 5);
  });

  testWidgets('the range is marked while the finger is down', (tester) async {
    await pump(tester);
    await dragRange(
      tester,
      find.text('5').last,
      find.text('8').last,
      release: false,
    );
    expect(find.text('Drag to line…'), findsOneWidget);
    // Nothing is posted until the finger comes up.
    expect(anchors, isEmpty);

    await tester.pumpAndSettle();
  });
}
