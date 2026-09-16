import 'package:boardhop/features/pull_requests/diff/diff_model.dart';
import 'package:boardhop/features/pull_requests/diff/diff_view.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:mocktail/mocktail.dart';

import 'diff_page_harness.dart';

class _FallbackPr extends Fake implements PullRequest {}

/// R9's left side: a thread anchored on the original file renders under the
/// removed line it belongs to, and the gutter of a removed line posts one.
void main() {
  late List<DiffAnchor> tapped;

  Future<void> pump(
    WidgetTester tester, {
    List<dynamic> threads = const [],
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(
          body: DiffView(
            diff: LineDiff.compute(kOneOld, kOneNew),
            oldRuns: const [],
            newRuns: const [],
            canAct: true,
            threads: threads.cast(),
            onGutterTap: tapped.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUpAll(() => registerFallbackValue(_FallbackPr()));

  setUp(() => tapped = []);

  testWidgets('a left-side thread renders, keyed by the original line', (
    tester,
  ) async {
    await pump(
      tester,
      threads: [prThread(id: 42974, leftLine: 5, content: 'why did this go?')],
    );
    expect(find.textContaining('why did this go?'), findsOneWidget);
    // Directly under the removed line it is anchored to, above the added
    // one that replaced it.
    expect(
      tester.getCenter(find.textContaining('why did this go?')).dy,
      greaterThan(tester.getCenter(find.text('echo')).dy),
    );
    expect(
      tester.getCenter(find.textContaining('why did this go?')).dy,
      lessThan(tester.getCenter(find.text('foxtrot')).dy),
    );
  });

  testWidgets('a right-side thread still renders under its new line', (
    tester,
  ) async {
    await pump(
      tester,
      threads: [prThread(id: 1, rightLine: 5, content: 'on the new side')],
    );
    expect(
      tester.getCenter(find.textContaining('on the new side')).dy,
      greaterThan(tester.getCenter(find.text('ECHO')).dy),
    );
  });

  testWidgets('the gutter of a removed line posts on the left side', (
    tester,
  ) async {
    await pump(tester);
    // The removed line's row carries the old number in the first column.
    await tester.tap(find.text('5').first);
    await tester.pumpAndSettle();
    expect(tapped.single.leftSide, isTrue);
    expect(tapped.single.line, 5);

    await tester.tap(find.text('5').last);
    await tester.pumpAndSettle();
    expect(tapped.last.leftSide, isFalse);
    expect(tapped.last.line, 5);
  });

  testWidgets('a file-level thread renders above the first hunk (R9)', (
    tester,
  ) async {
    await pump(
      tester,
      threads: [prThread(id: 42973, content: 'a note on the whole file')],
    );
    expect(
      tester.getCenter(find.textContaining('a note on the whole file')).dy,
      lessThan(tester.getCenter(find.text('alpha')).dy),
    );
  });

  testWidgets('Comment on file opens a composer above the first hunk and '
      'posts with no line', (tester) async {
    final harness = await pumpDiffPage(tester);
    when(
      () => harness.repo.addThread(
        any(),
        any(),
        content: any(named: 'content'),
        filePath: any(named: 'filePath'),
        line: any(named: 'line'),
        endLine: any(named: 'endLine'),
        leftSide: any(named: 'leftSide'),
        fileLevel: any(named: 'fileLevel'),
        changeTrackingId: any(named: 'changeTrackingId'),
        iteration: any(named: 'iteration'),
      ),
    ).thenAnswer((_) async => 1);

    await tester.tap(find.byTooltip('Diff options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comment on file'));
    await tester.pumpAndSettle();
    expect(find.text('Comment on this file'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Comment on this file')).dy,
      lessThan(tester.getCenter(find.text('alpha')).dy),
    );

    await tester.enterText(find.byType(TextField).first, 'a file note');
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    final call = verify(
      () => harness.repo.addThread(
        'o',
        any(),
        content: 'a file note',
        filePath: kOnePath,
        line: captureAny(named: 'line'),
        endLine: any(named: 'endLine'),
        leftSide: captureAny(named: 'leftSide'),
        fileLevel: captureAny(named: 'fileLevel'),
        changeTrackingId: any(named: 'changeTrackingId'),
        iteration: any(named: 'iteration'),
      ),
    )..called(1);
    // mocktail hands the captures back in its own order for named
    // arguments: leftSide, fileLevel, line.
    expect(call.captured, [false, true, null]);
  });

  testWidgets('the gutter of a removed line posts leftSide through the '
      'repository', (tester) async {
    final harness = await pumpDiffPage(tester);
    when(
      () => harness.repo.addThread(
        any(),
        any(),
        content: any(named: 'content'),
        filePath: any(named: 'filePath'),
        line: any(named: 'line'),
        endLine: any(named: 'endLine'),
        leftSide: any(named: 'leftSide'),
        fileLevel: any(named: 'fileLevel'),
        changeTrackingId: any(named: 'changeTrackingId'),
        iteration: any(named: 'iteration'),
      ),
    ).thenAnswer((_) async => 1);

    await tester.tap(find.text('5').first);
    await tester.pumpAndSettle();
    expect(find.text('Comment on line 5 (original)'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'gone why?');
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    final call = verify(
      () => harness.repo.addThread(
        'o',
        any(),
        content: 'gone why?',
        filePath: kOnePath,
        line: captureAny(named: 'line'),
        endLine: captureAny(named: 'endLine'),
        leftSide: captureAny(named: 'leftSide'),
        fileLevel: any(named: 'fileLevel'),
        changeTrackingId: any(named: 'changeTrackingId'),
        iteration: any(named: 'iteration'),
      ),
    )..called(1);
    // leftSide, line, endLine: a single line on the original side.
    expect(call.captured, [true, 5, null]);
  });
}
