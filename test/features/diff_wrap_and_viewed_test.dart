import 'package:boardhop/features/pull_requests/diff/diff_prefs.dart';
import 'package:boardhop/features/pull_requests/diff/diff_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'diff_page_harness.dart';

/// R8's viewed mark on the diff's app bar and R16's wrap and side-by-side
/// toggles in its overflow.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the check marks the file as viewed and back', (tester) async {
    final harness = await pumpDiffPage(tester);
    expect(find.byTooltip('Mark as viewed'), findsOneWidget);
    expect(await harness.viewed.isViewed('o', 8401, kOnePath), isFalse);

    await tester.tap(find.byTooltip('Mark as viewed'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Viewed'), findsOneWidget);
    expect(await harness.viewed.isViewed('o', 8401, kOnePath), isTrue);
    // The mark carries the blob it was made against, so a later push
    // clears it (R8).
    expect(
      (await harness.viewed.marks('o', 8401))[kOnePath]?.objectId,
      'blob-one',
    );
    // Marking advances nothing: the same file is still on screen.
    expect(find.text('one.dart'), findsOneWidget);

    await tester.tap(find.byTooltip('Viewed'));
    await tester.pumpAndSettle();
    expect(await harness.viewed.isViewed('o', 8401, kOnePath), isFalse);
  });

  testWidgets('v marks it from the keyboard (R16)', (tester) async {
    final harness = await pumpDiffPage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    expect(await harness.viewed.isViewed('o', 8401, kOnePath), isTrue);
  });

  testWidgets('v typed into a comment is a letter, not a mark', (tester) async {
    final harness = await pumpDiffPage(tester);
    await tester.tap(find.text('2').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'v');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    expect(await harness.viewed.isViewed('o', 8401, kOnePath), isFalse);
  });

  testWidgets('the mark follows the file the reader steps into', (
    tester,
  ) async {
    final harness = await pumpDiffPage(tester);
    await tester.tap(find.byTooltip('Mark as viewed'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pumpAndSettle();
    expect(find.text('two.dart'), findsOneWidget);
    // The second file is not viewed, and the first one still is.
    expect(find.byTooltip('Mark as viewed'), findsOneWidget);
    expect(await harness.viewed.isViewed('o', 8401, kOnePath), isTrue);
    expect(await harness.viewed.isViewed('o', 8401, kTwoPath), isFalse);
  });

  testWidgets('the overflow wraps long lines and remembers it', (tester) async {
    await pumpDiffPage(tester);
    expect(tester.widget<DiffView>(find.byType(DiffView)).wrap, isFalse);

    await tester.tap(find.byTooltip('Diff options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wrap long lines'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(tester.widget<DiffView>(find.byType(DiffView)).wrap, isTrue);
    expect(await DiffPrefs.wrap('u1'), isTrue);
  });

  testWidgets('the overflow switches the panes and remembers it', (
    tester,
  ) async {
    await pumpDiffPage(tester);
    expect(tester.widget<DiffView>(find.byType(DiffView)).sideBySide, isFalse);

    await tester.tap(find.byTooltip('Diff options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Side by side'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(tester.widget<DiffView>(find.byType(DiffView)).sideBySide, isTrue);
    expect(await DiffPrefs.sideBySide('u1'), isTrue);
  });

  testWidgets('a remembered choice beats the breakpoint default', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'diff_side_by_side:u1': false});
    await pumpDiffPage(
      tester,
      size: const Size(2400, 1600),
      devicePixelRatio: 2,
    );
    // An expanded window would open two panes; the reader said otherwise.
    expect(tester.widget<DiffView>(find.byType(DiffView)).sideBySide, isFalse);
  });
}
